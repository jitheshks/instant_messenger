import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/migrations/legacy_chat_cache_migration.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';

import 'stores/messages_store.dart';
import 'stores/chats_store.dart';
import 'stores/outbox_store.dart';
import 'stores/sync_cursors_store.dart';
import 'stores/attachments_store.dart';

/// Centralized Hive CE local persistence engine with multi-account isolation.
///
/// Ensures all local data is namespaced per user account.
/// On logout or account switch, calling [close] disposes all opened boxes,
/// ensuring zero cross-account data leaks while preserving offline caches.
class HiveDatabase {
  final String accountId;
  final MessagesStore messagesStore;
  final ChatsStore chatsStore;
  final OutboxStore outboxStore;
  final SyncCursorsStore syncCursorsStore;
  final AttachmentsStore attachmentsStore;
  OutboxDaemon? outboxDaemon;
  ReconciliationService? reconciliationService;
  RealtimeConnectionManager? realtimeConnectionManager;

  HiveDatabase({
    required this.accountId,
    required this.messagesStore,
    required this.chatsStore,
    required this.outboxStore,
    required this.syncCursorsStore,
    required this.attachmentsStore,
    this.outboxDaemon,
    this.reconciliationService,
    this.realtimeConnectionManager,
  });

  /// Opens or retrieves an account-isolated Hive CE database for [accountId].
  ///
  /// Box names:
  /// - Messages: `cache_msgs_$accountId` (interoperable with [MessageCache])
  /// - Chats: `chats_cache_$accountId`
  /// - Outbox: `outbox_mutations_$accountId`
  /// - Sync Cursors: `sync_cursors_$accountId`
  /// - Attachments: `attachments_$accountId`
  static Future<HiveDatabase> openForAccount(String accountId) async {
    assert(accountId.isNotEmpty, 'accountId cannot be empty');

    // 1. Ensure adapters are registered before opening any box
    HiveInit.registerAdapters();

    // 2. Open account-namespaced boxes
    final msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
    final chatBox = await Hive.openBox('chats_cache_$accountId');
    final outboxBox = await Hive.openBox('outbox_mutations_$accountId');
    final cursorBox = await Hive.openBox('sync_cursors_$accountId');
    final attachmentBox = await Hive.openBox('attachments_$accountId');

    final db = HiveDatabase(
      accountId: accountId,
      messagesStore: MessagesStore(msgBox),
      chatsStore: ChatsStore(chatBox),
      outboxStore: OutboxStore(outboxBox),
      syncCursorsStore: SyncCursorsStore(cursorBox),
      attachmentsStore: AttachmentsStore(attachmentBox),
    );

    // 3. Migrate legacy chat_cache summaries if present
    try {
      await LegacyChatCacheMigration.migrate(
        accountId: accountId,
        targetStore: db.chatsStore,
      );
    } catch (e) {
      debugPrint('[HiveDatabase] Non-fatal legacy chat migration notice: $e');
    }

    // 4. Recover any in-flight outbox mutations abandoned by unexpected termination
    try {
      await db.outboxStore.recoverInFlight();
    } catch (e) {
      debugPrint('[HiveDatabase] Non-fatal outbox recovery notice: $e');
    }

    // 4b. Recover latest conversation previews from MessagesStore (crash consistency)
    try {
      await db.chatsStore.recoverLatestPreviews(
        db.messagesStore,
        accountId,
        outboxStore: db.outboxStore,
      );
    } catch (e) {
      debugPrint('[HiveDatabase] Non-fatal chat preview recovery notice: $e');
    }

    // 5. Initialize and start the durable OutboxDaemon for background dispatch
    try {
      final daemon = OutboxDaemon(
        accountId: accountId,
        outboxStore: db.outboxStore,
        messagesStore: db.messagesStore,
        chatsStore: db.chatsStore,
      );
      await daemon.start();
      db.outboxDaemon = daemon;
    } catch (e) {
      debugPrint(
        '[HiveDatabase] Non-fatal outbox daemon initialization notice: $e',
      );
    }

    // 5b. Initialize and start RealtimeConnectionManager for socket lifecycle and single-flight recovery
    try {
      final rcm = RealtimeConnectionManager(
        accountId: accountId,
        connectivityService: db.outboxDaemon?.connectivityService,
        onCatchUp: () async {
          if (db.reconciliationService != null && !db.reconciliationService!.isClosed) {
            await db.reconciliationService!.syncMessages();
          }
        },
      );
      await rcm.start();
      db.realtimeConnectionManager = rcm;
    } catch (e) {
      debugPrint(
        '[HiveDatabase] Non-fatal RealtimeConnectionManager initialization notice: $e',
      );
    }

    // 6. Initialize and start ReconciliationService for two-way synchronization
    try {
      final recon = ReconciliationService(
        accountId: accountId,
        messagesStore: db.messagesStore,
        chatsStore: db.chatsStore,
        syncCursorsStore: db.syncCursorsStore,
        outboxDaemon: db.outboxDaemon,
        connectivityService: db.outboxDaemon?.connectivityService,
        connectionManager: db.realtimeConnectionManager,
      );
      unawaited(recon.startRealtime());
      if (recon.connectivityService == null ||
          recon.connectivityService!.hasNetworkInterface) {
        unawaited(recon.syncMessages());
      }
      db.reconciliationService = recon;
    } catch (e) {
      debugPrint(
        '[HiveDatabase] Non-fatal reconciliation service initialization notice: $e',
      );
    }

    return db;
  }

  /// Closes all boxes associated with this account.
  ///
  /// Preserves all local data on disk. Only in-memory handles and locks are released.
  Future<void> close() async {
    if (realtimeConnectionManager != null) {
      await realtimeConnectionManager!.stop();
      realtimeConnectionManager = null;
    }
    if (reconciliationService != null) {
      await reconciliationService!.stop();
      reconciliationService = null;
    }
    if (outboxDaemon != null) {
      await outboxDaemon!.stop();
      outboxDaemon = null;
    }
    if (messagesStore.box.isOpen) await messagesStore.box.close();
    if (chatsStore.box.isOpen) await chatsStore.box.close();
    if (outboxStore.box.isOpen) await outboxStore.box.close();
    if (syncCursorsStore.box.isOpen) await syncCursorsStore.box.close();
    if (attachmentsStore.box.isOpen) await attachmentsStore.box.close();
  }
}

/// Coordinates active account lifecycle and clean store disposal across sign-in/sign-out.
class HiveDatabaseManager {
  HiveDatabaseManager._();
  static final HiveDatabaseManager instance = HiveDatabaseManager._();

  HiveDatabase? _activeDatabase;

  /// Currently active [HiveDatabase], or null if unauthenticated.
  HiveDatabase? get activeDatabase => _activeDatabase;

  /// Whether an account database is currently open.
  bool get hasActiveDatabase => _activeDatabase != null;

  /// Opens an account database for [accountId], closing any previously active account first.
  Future<HiveDatabase> openAccount(String accountId) async {
    if (_activeDatabase?.accountId == accountId) {
      return _activeDatabase!;
    }

    if (_activeDatabase != null) {
      await closeCurrentAccount();
    }

    final db = await HiveDatabase.openForAccount(accountId);
    _activeDatabase = db;
    return db;
  }

  /// Closes the currently active account database without deleting offline cache data.
  Future<void> closeCurrentAccount() async {
    final db = _activeDatabase;
    _activeDatabase = null;
    try {
      await LocalCache.onSignOut();
    } catch (_) {}
    if (db != null) {
      await db.close();
    }
  }

  /// Explicit testing hook to inject an active database without running file I/O.
  @visibleForTesting
  void setActiveDatabaseForTesting(HiveDatabase? db) {
    _activeDatabase = db;
  }
}
