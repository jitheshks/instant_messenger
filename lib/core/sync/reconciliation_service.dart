import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/sync_cursors_store.dart';
import 'package:instant_messenger/core/sync/chat_preview_ordering_policy.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReconciliationEventType { inserted, updated, deduplicated, ignored }

class ReconciliationEvent {
  final String messageId;
  final String chatId;
  final ReconciliationEventType type;
  final DateTime timestamp;

  const ReconciliationEvent({
    required this.messageId,
    required this.chatId,
    required this.type,
    required this.timestamp,
  });

  @override
  String toString() =>
      'ReconciliationEvent($type, id: $messageId, chat: $chatId)';
}

/// Orchestrates remote-to-local synchronization and Realtime reconciliation.
///
/// Converts Supabase Realtime changes and remote query batches into
/// canonical, account-scoped Hive CE records without regressions.
class ReconciliationService {
  final String accountId;
  final MessagesStore messagesStore;
  final ChatsStore? chatsStore;
  final SyncCursorsStore? syncCursorsStore;
  final OutboxDaemon? outboxDaemon;
  final SupabaseClient? supabaseClient;
  final ConnectivityService? connectivityService;
  final RealtimeConnectionManager? connectionManager;
  final Future<List<Map<String, dynamic>>> Function(
    DateTime after,
    String? lastId,
    int limit,
  )?
  defaultFetcher;

  RealtimeChannel? _channel;
  StreamSubscription<NetworkInterfaceStatus>? _connectivitySub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _reconnectTimer;
  bool _isClosed = false;
  bool _hasSubscribedOnce = false;

  Completer<void>? _activeSyncCompleter;
  final _recentDeliveryAcks = <String>{};

  final _eventsController = StreamController<ReconciliationEvent>.broadcast();
  final _errorsController = StreamController<Object>.broadcast();

  Stream<ReconciliationEvent> get events => _eventsController.stream;
  Stream<Object> get errors => _errorsController.stream;

  bool get isClosed => _isClosed;

  static const int defaultBatchSize = 100;
  static const int maxPagesPerSync = 20;

  ReconciliationService({
    required this.accountId,
    required this.messagesStore,
    this.chatsStore,
    this.syncCursorsStore,
    this.outboxDaemon,
    this.supabaseClient,
    this.connectivityService,
    this.connectionManager,
    this.defaultFetcher,
  });

  SupabaseClient? get _safeSb {
    if (supabaseClient != null) return supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Starts listening to Supabase Realtime for messages and attaches reconnect catch-up.
  Future<void> startRealtime() async {
    if (_isClosed) return;

    // 1. Listen for connectivity restoration to trigger catch-up
    if (connectivityService != null && _connectivitySub == null) {
      _connectivitySub = connectivityService!.onStatusChanged.listen(
        (status) {
          if (status.hasInterface && !_isClosed && messagesStore.box.isOpen) {
            debugPrint(
              '[ReconciliationService] Network interface restored -> triggering catch-up sync',
            );
            unawaited(syncMessages());
          }
        },
        onError: (err) {
          debugPrint('[ReconciliationService] Connectivity stream notice: $err');
        },
      );
    }

    final sb = _safeSb;
    if (sb == null) return;

    if (_authSub == null) {
      try {
        _authSub = sb.auth.onAuthStateChange.listen((data) {
          if (_isClosed || !messagesStore.box.isOpen) return;
          final event = data.event;
          if (event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.signedIn) {
            debugPrint(
              '[ReconciliationService] Auth token refreshed ($event) -> reconnecting Realtime',
            );
            unawaited(reconnectRealtime());
          }
        });
      } catch (e) {
        debugPrint('[ReconciliationService] authStateChange listen notice: $e');
      }
    }

    await _subscribeRealtime(sb);
  }

  Future<void> _subscribeRealtime(SupabaseClient sb) async {
    if (_isClosed || !messagesStore.box.isOpen) return;

    try {
      final channelName = 'reconciliation:$accountId';
      connectionManager?.registerRequiredChannel(channelName);
      _channel = sb.channel(channelName);
      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              if (_isClosed || !messagesStore.box.isOpen) return;
              final record = payload.newRecord;
              if (record.isNotEmpty) {
                unawaited(reconcileRemoteMessage(record));
              }
            },
          )
          .subscribe((status, [error]) {
            if (_isClosed) return;
            if (error != null) {
              _errorsController.add(error);
            }
            connectionManager?.reportChannelStatus(channelName, status, error);
            handleRealtimeStatus(status);
          });
    } catch (e) {
      if (!_isClosed) {
        debugPrint('[ReconciliationService] Realtime subscription error: $e');
        _errorsController.add(e);
      }
    }
  }

  /// Reconnects the Realtime subscription and triggers catch-up sync.
  Future<void> reconnectRealtime() async {
    if (_isClosed || !messagesStore.box.isOpen) return;
    _reconnectTimer?.cancel();
    final sb = _safeSb;
    if (sb == null) return;

    debugPrint(
      '[ReconciliationService] Reconnecting Realtime channel for account $accountId',
    );
    try {
      if (_channel != null) {
        await sb.removeChannel(_channel!);
        _channel = null;
      }
    } catch (_) {}

    await _subscribeRealtime(sb);
    unawaited(syncMessages());
  }

  void _scheduleRealtimeReconnect() {
    if (_isClosed || !messagesStore.box.isOpen) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (!_isClosed && messagesStore.box.isOpen) {
        unawaited(reconnectRealtime());
      }
    });
  }

  /// Handles Realtime subscription status changes and triggers initial/reconnect catch-up sync.
  @visibleForTesting
  void handleRealtimeStatus(RealtimeSubscribeStatus status) {
    if (_isClosed || !messagesStore.box.isOpen) return;
    if (status == RealtimeSubscribeStatus.subscribed) {
      _reconnectTimer?.cancel();
      if (_hasSubscribedOnce) {
        debugPrint(
          '[ReconciliationService] Realtime reconnected -> triggering catch-up sync',
        );
        unawaited(syncMessages());
      } else {
        _hasSubscribedOnce = true;
        debugPrint(
          '[ReconciliationService] Realtime initial subscription confirmed -> triggering initial sync',
        );
        unawaited(syncMessages());
      }
    } else if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      debugPrint(
        '[ReconciliationService] Realtime subscription status: $status -> channel error',
      );
      if (connectionManager == null) {
        _scheduleRealtimeReconnect();
      }
    }
  }

  /// Reconciles a single remote database record into local Hive persistence.
  ///
  /// Guarantees:
  /// 1. Idempotent: repeated calls with the same record produce the same state.
  /// 2. Monotonic: delivery states never regress (`read`/`delivered` won't drop to `sent`).
  /// 3. Convergent: optimistic local messages merge with the server record on matching ID.
  /// 4. Outbox sync: server confirmation clears queued send mutations.
  /// 5. Delivery acknowledgement: incoming messages stored locally trigger remote delivery receipt.
  Future<void> reconcileRemoteMessage(
    Map<String, dynamic> record, {
    bool strict = false,
    bool autoAcknowledgeDelivery = true,
  }) async {
    if (_isClosed || !messagesStore.box.isOpen) return;

    try {
      final remoteMsg = ChatMessage.fromSupabase(record, accountId);
      if (remoteMsg.id.isEmpty) return;

      final existing = messagesStore.getMessage(remoteMsg.id);
      final isNew = existing == null;

      // Save into Hive (MessagesStore internally applies monotonic merge rules)
      await messagesStore.saveMessage(remoteMsg);

      // Confirm to OutboxDaemon if status is sent or higher
      if (remoteMsg.deliveryState.index >= DeliveryState.sent.index) {
        if (outboxDaemon != null) {
          unawaited(outboxDaemon!.onMessageConfirmed(remoteMsg.id));
        }
      }

      // Update ChatsStore summary if available
      if (chatsStore != null && remoteMsg.chatId.isNotEmpty) {
        _updateChatSummaryLastMessage(remoteMsg);
      }

      // Acknowledge delivery for incoming messages stored locally that are not yet marked delivered
      if (autoAcknowledgeDelivery &&
          remoteMsg.isIncoming &&
          remoteMsg.deliveryState.index < DeliveryState.delivered.index) {
        unawaited(acknowledgeDelivery([remoteMsg.id]));
      }

      if (!_eventsController.isClosed) {
        _eventsController.add(
          ReconciliationEvent(
            messageId: remoteMsg.id,
            chatId: remoteMsg.chatId,
            type: isNew
                ? ReconciliationEventType.inserted
                : ReconciliationEventType.updated,
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ReconciliationService] Error reconciling record: $e');
      if (!_errorsController.isClosed) {
        _errorsController.add(e);
      }
      if (strict) {
        rethrow;
      }
    }
  }

  /// Dispatches delivery acknowledgement for received incoming messages.
  ///
  /// Guarantees:
  /// 1. Idempotent: duplicate calls for the same message IDs are deduplicated.
  /// 2. Monotonic: updates local store to `delivered` before/alongside network call.
  /// 3. Offline-aware: defers remote RPC if network interface is not available.
  /// 4. Bounded: cache of recent acks is capped to prevent memory growth.
  Future<void> acknowledgeDelivery(List<String> messageIds) async {
    if (messageIds.isEmpty || _isClosed) return;

    final sb = _safeSb;
    if (sb == null) return;

    // If offline or backend unreachable, defer remote RPC until connectivity is restored
    if (connectivityService != null &&
        (!connectivityService!.hasNetworkInterface ||
            connectivityService!.backendReachabilityStatus ==
                BackendReachabilityStatus.unreachable)) {
      return;
    }

    final toAck = messageIds
        .where((id) => id.isNotEmpty && !_recentDeliveryAcks.contains(id))
        .toList();
    if (toAck.isEmpty) return;

    for (final id in toAck) {
      _recentDeliveryAcks.add(id);
      if (_recentDeliveryAcks.length > 500) {
        _recentDeliveryAcks.remove(_recentDeliveryAcks.first);
      }
    }

    // 1. Advance local state in MessagesStore to delivered state
    for (final id in toAck) {
      try {
        await messagesStore.updateDelivery(id, DeliveryState.delivered);
      } catch (_) {}
    }

    // 2. Dispatch promote_message_status RPC to Supabase
    try {
      await sb.rpc(
        'promote_message_status',
        params: {
          'p_message_ids': toAck,
          'p_new_status': DeliveryState.delivered.index,
        },
      );
    } catch (e) {
      debugPrint('[ReconciliationService] promote_message_status error: $e');
      for (final id in toAck) {
        _recentDeliveryAcks.remove(id);
      }
    }
  }

  /// Reconciles a batch of remote message records in sequence.
  Future<void> reconcileRemoteMessages(
    List<Map<String, dynamic>> records,
  ) async {
    if (_isClosed || !messagesStore.box.isOpen || records.isEmpty) return;
    final toDeliverIds = <String>[];
    for (final record in records) {
      final remoteMsg = ChatMessage.fromSupabase(record, accountId);
      if (remoteMsg.id.isNotEmpty &&
          remoteMsg.isIncoming &&
          remoteMsg.deliveryState.index < DeliveryState.delivered.index) {
        toDeliverIds.add(remoteMsg.id);
      }
      await reconcileRemoteMessage(record, autoAcknowledgeDelivery: false);
    }
    if (toDeliverIds.isNotEmpty) {
      unawaited(acknowledgeDelivery(toDeliverIds));
    }
  }

  /// Pulls incremental message batches using compound cursors and drains backlogs.
  ///
  /// Guarantees:
  /// 1. Serialized: concurrent calls are queued to prevent cursor race conditions.
  /// 2. Deterministic: compound ordering by `sent_at ASC, id ASC`.
  /// 3. Starvation-free: records sharing the same timestamp are paginated monotonically.
  /// 4. Multi-page: drains backlog across multiple pages up to [maxPages].
  /// 5. Crash-safe: advances cursor ONLY AFTER local persistence succeeds.
  Future<int> syncMessages({
    String? chatId,
    int batchSize = defaultBatchSize,
    int maxPages = maxPagesPerSync,
    Future<List<Map<String, dynamic>>> Function(
      DateTime after,
      String? lastId,
      int limit,
    )?
    customFetcher,
  }) async {
    if (_isClosed || !messagesStore.box.isOpen) return 0;

    // Serialize execution to prevent concurrent cursor read/commit races
    while (_activeSyncCompleter != null) {
      await _activeSyncCompleter!.future;
      if (_isClosed || !messagesStore.box.isOpen) return 0;
    }

    final completer = Completer<void>();
    _activeSyncCompleter = completer;

    try {
      final total = await _executeSyncMessages(
        chatId: chatId,
        batchSize: batchSize,
        maxPages: maxPages,
        customFetcher: customFetcher,
      );
      return total;
    } finally {
      _activeSyncCompleter = null;
      completer.complete();
    }
  }

  Future<int> _executeSyncMessages({
    String? chatId,
    required int batchSize,
    required int maxPages,
    Future<List<Map<String, dynamic>>> Function(
      DateTime after,
      String? lastId,
      int limit,
    )?
    customFetcher,
  }) async {
    if (_isClosed || !messagesStore.box.isOpen) return 0;

    final cursorKey = chatId != null
        ? 'chat_messages_${accountId}_$chatId'
        : 'messages_$accountId';

    int totalSynced = 0;
    int pageCount = 0;

    while (pageCount < maxPages && !_isClosed && messagesStore.box.isOpen) {
      pageCount++;

      final cursor = syncCursorsStore?.getCursor(cursorKey);
      final fromMicros = cursor?.lastSyncTimestamp ?? 0;
      final fromId = cursor?.lastSyncId;
      final fromIsoStored = cursor?.lastSyncIso;
      final fromDateTime = fromMicros > 0
          ? DateTime.fromMicrosecondsSinceEpoch(fromMicros, isUtc: true)
          : DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      final fromIso =
          fromIsoStored ??
          (fromMicros > 0 ? fromDateTime.toIso8601String() : null);

      List<Map<String, dynamic>> rawBatch;

      try {
        final fetcher = customFetcher ?? defaultFetcher;
        if (fetcher != null) {
          rawBatch = await fetcher(fromDateTime, fromId, batchSize);
        } else {
          if (connectivityService != null &&
              (!connectivityService!.hasNetworkInterface ||
                  connectivityService!.backendReachabilityStatus ==
                      BackendReachabilityStatus.unreachable)) {
            debugPrint(
              '[ReconciliationService] No active network interface or backend unreachable. Skipping network fetch.',
            );
            break;
          }
          final sb = _safeSb;
          if (sb == null) break;

          var query = sb.from('messages').select();
          if (chatId != null && chatId.isNotEmpty) {
            query = query.eq('chat_id', chatId);
          }
          if (fromMicros > 0 && fromId != null && fromId.isNotEmpty) {
            final queryIso = fromIso!;
            query = query.or(
              'sent_at.gt.$queryIso,and(sent_at.eq.$queryIso,id.gt.$fromId)',
            );
          } else if (fromMicros > 0) {
            final queryIso = fromIso!;
            query = query.gt('sent_at', queryIso);
          }
          final res = await query
              .order('sent_at', ascending: true)
              .order('id', ascending: true)
              .limit(batchSize);
          rawBatch = (res as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (e) {
        debugPrint('[ReconciliationService] Incremental sync fetch error: $e');
        if (!_errorsController.isClosed) {
          _errorsController.add(e);
        }
        break;
      }

      if (rawBatch.isEmpty || _isClosed || !messagesStore.box.isOpen) break;

      // Filter boundary duplicates: keep only records strictly after the compound cursor
      final filtered = <Map<String, dynamic>>[];
      for (final row in rawBatch) {
        final rowId = row['id']?.toString();
        final rowMicros = _parseTimestamp(row['sent_at']);
        if (_isAfterCursor(rowMicros, rowId, fromMicros, fromId)) {
          filtered.add(row);
        }
      }

      if (filtered.isEmpty) {
        // No records strictly after current cursor
        if (rawBatch.length < batchSize) {
          break;
        }
        // If rawBatch was full batch but produced no forward records, break to prevent infinite loop
        debugPrint(
          '[ReconciliationService] Notice: Server batch contained ${rawBatch.length} records but none were after cursor ($fromMicros, $fromId). Terminating sync pass.',
        );
        break;
      }

      // 1. Reconcile and persist records, tracking the last successfully persisted record
      Map<String, dynamic>? lastPersistedRecord;
      bool persistenceFailed = false;
      final pendingDeliveryIds = <String>[];

      for (final row in filtered) {
        try {
          final remoteMsg = ChatMessage.fromSupabase(row, accountId);
          if (remoteMsg.id.isNotEmpty &&
              remoteMsg.isIncoming &&
              remoteMsg.deliveryState.index < DeliveryState.delivered.index) {
            pendingDeliveryIds.add(remoteMsg.id);
          }
          await reconcileRemoteMessage(
            row,
            strict: true,
            autoAcknowledgeDelivery: false,
          );
          lastPersistedRecord = row;
        } catch (e) {
          debugPrint('[ReconciliationService] Local persistence error: $e');
          persistenceFailed = true;
          break;
        }
      }

      if (pendingDeliveryIds.isNotEmpty) {
        unawaited(acknowledgeDelivery(pendingDeliveryIds));
      }

      if (_isClosed || !messagesStore.box.isOpen) break;

      // 2. Commit cursor ONLY up to the last successfully persisted record
      if (lastPersistedRecord != null) {
        final lastMicros = _parseTimestamp(lastPersistedRecord['sent_at']);
        final lastId = lastPersistedRecord['id']?.toString();
        final lastIso = _formatTimestampIso(lastPersistedRecord['sent_at']);

        if (_isAfterCursor(lastMicros, lastId, fromMicros, fromId)) {
          if (syncCursorsStore != null && syncCursorsStore!.box.isOpen) {
            await syncCursorsStore!.setCursor(
              cursorKey,
              lastMicros,
              syncId: lastId,
              isoString: lastIso,
            );
          }
        }
        totalSynced += filtered.indexOf(lastPersistedRecord) + 1;
      }

      if (persistenceFailed) {
        // Do not continue to next page if persistence failed on this page
        break;
      }

      // If rawBatch returned fewer records than batchSize, we have drained the backlog
      if (rawBatch.length < batchSize) {
        break;
      }
    }

    if (pageCount >= maxPages) {
      debugPrint(
        '[ReconciliationService] Safety limit reached ($maxPages pages). Incremental sync paused with committed cursor.',
      );
    }

    return totalSynced;
  }

  /// Strictly determines whether (rowMicros, rowId) is monotonically after (cursorMicros, cursorId).
  ///
  /// Enforces server ordering:
  /// Primary ordering: `sent_at ASC` (represented by full-precision epoch microseconds).
  /// Secondary ordering: `id ASC` (tie-breaker ONLY for genuinely equal timestamps).
  static bool _isAfterCursor(
    int rowMicros,
    String? rowId,
    int cursorMicros,
    String? cursorId,
  ) {
    if (cursorMicros <= 0) return true;
    if (rowMicros > cursorMicros) return true;
    if (rowMicros == cursorMicros) {
      if (cursorId == null || cursorId.isEmpty) return true;
      if (rowId == null || rowId.isEmpty) return false;
      return rowId.compareTo(cursorId) > 0;
    }
    return false;
  }

  static int _parseTimestamp(dynamic raw) {
    if (raw is int) {
      // If integer is already microseconds (> 10^14), return as-is.
      // If integer is milliseconds (< 10^14 and > 0), convert to microseconds.
      if (raw > 100000000000000) return raw;
      if (raw > 0) return raw * 1000;
      return raw;
    }
    if (raw is DateTime) return raw.toUtc().microsecondsSinceEpoch;
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc().microsecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  static String? _formatTimestampIso(dynamic raw) {
    if (raw is String) {
      final dt = DateTime.tryParse(raw)?.toUtc();
      return dt?.toIso8601String() ?? raw;
    }
    if (raw is DateTime) {
      return raw.toUtc().toIso8601String();
    }
    if (raw is int) {
      final micros = raw > 100000000000000 ? raw : raw * 1000;
      if (micros <= 0) return null;
      return DateTime.fromMicrosecondsSinceEpoch(
        micros,
        isUtc: true,
      ).toIso8601String();
    }
    return null;
  }

  void _updateChatSummaryLastMessage(ChatMessage msg) {
    if (_isClosed || chatsStore == null || !chatsStore!.box.isOpen) return;
    try {
      final summary = chatsStore!.getChatSummary(msg.chatId);
      if (summary != null) {
        // Safeguard 1 & 7: Conservative tie policy
        final action = ChatPreviewOrderingPolicy.evaluate(
          candidateTime: msg.sentAt,
          candidateMessageId: msg.id,
          existingTime: summary.lastTime,
          existingMessageId: summary.lastMessageId,
        );

        if (action == CandidateAction.ignoreCandidate) {
          return;
        }

        if (action == CandidateAction.updateStatusOnly) {
          if (msg.statusInt > summary.lastMessageStatus) {
            chatsStore!.saveChatSummary(
              summary.copyWith(lastMessageStatus: msg.statusInt),
            );
          }
          return;
        }

        final updated = summary.copyWith(
          lastMessage: ChatsStore.formatMessagePreview(msg),
          lastTime: msg.sentAt,
          lastSenderId: msg.senderId,
          lastMessageStatus: msg.statusInt,
          lastMessageId: msg.id,
        );
        chatsStore!.saveChatSummary(updated);
      }
    } catch (e) {
      debugPrint(
        '[ReconciliationService] Non-fatal chat summary update notice: $e',
      );
    }
  }

  /// Disposes Realtime subscriptions, cancels connectivity listeners, and closes event streams.
  Future<void> stop() async {
    if (_isClosed) return;
    _isClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      if (_authSub != null) {
        await _authSub!.cancel();
        _authSub = null;
      }
      if (_connectivitySub != null) {
        await _connectivitySub!.cancel();
        _connectivitySub = null;
      }
      connectionManager?.unregisterChannel('reconciliation:$accountId');
      if (_channel != null) {
        final sb = _safeSb;
        if (sb != null) {
          await sb.removeChannel(_channel!);
        } else {
          await _channel!.unsubscribe();
        }
        _channel = null;
      }
    } catch (e) {
      debugPrint('[ReconciliationService] Notice during unsubscribe: $e');
    }

    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
    if (!_errorsController.isClosed) {
      await _errorsController.close();
    }
  }
}
