import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/sync_cursors_store.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online = true;
  final _controller = StreamController<NetworkInterfaceStatus>.broadcast();

  _FakeConnectivityService({bool initialOnline = true})
    : _online = initialOnline;

  @override
  bool get hasNetworkInterface => _online;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => _controller.stream;

  void setOnline(bool online) {
    _online = online;
    _controller.add(
      NetworkInterfaceStatus([
        online ? NetworkInterfaceType.wifi : NetworkInterfaceType.none,
      ]),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Phase 4.1 Hardened — Reconnection Catch-Up & Serialization Tests (Task 2)',
    () {
      late Directory tempDir;
      late Box<ChatMessage> msgBox;
      late Box chatBox;
      late Box cursorBox;
      late MessagesStore messagesStore;
      late ChatsStore chatsStore;
      late SyncCursorsStore syncCursorsStore;
      late _FakeConnectivityService connectivity;

      const accountId = 'user-alice-catchup-test';
      const otherUserId = 'user-bob-catchup-test';
      const chatId = 'chat-catchup-101';

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('catchup_sync_test_');
        Hive.init(tempDir.path);
        HiveInit.registerAdapters();

        msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
        chatBox = await Hive.openBox('chats_cache_$accountId');
        cursorBox = await Hive.openBox('sync_cursors_$accountId');

        messagesStore = MessagesStore(msgBox);
        chatsStore = ChatsStore(chatBox);
        syncCursorsStore = SyncCursorsStore(cursorBox);
        connectivity = _FakeConnectivityService(initialOnline: false);
      });

      tearDown(() async {
        if (msgBox.isOpen) await msgBox.close();
        if (chatBox.isOpen) await chatBox.close();
        if (cursorBox.isOpen) await cursorBox.close();
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      test(
        'connectivity restoration triggers automatic catch-up sync and reconciles missed messages',
        () async {
          final missedSentAt = DateTime.utc(2026, 10, 24, 14, 0, 0);
          final missedRows = [
            {
              'id': 'msg-missed-offline-1',
              'chat_id': chatId,
              'sender_id': otherUserId,
              'text': 'Message while you were offline',
              'type': 'text',
              'status': 1,
              'sent_at': missedSentAt.toIso8601String(),
            },
          ];

          int fetchCount = 0;
          final service = ReconciliationService(
            accountId: accountId,
            messagesStore: messagesStore,
            chatsStore: chatsStore,
            syncCursorsStore: syncCursorsStore,
            connectivityService: connectivity,
            defaultFetcher: (after, lastId, limit) async {
              fetchCount++;
              return missedRows;
            },
          );

          // Start realtime listening with offline connectivity initially
          await service.startRealtime();
          expect(messagesStore.getMessage('msg-missed-offline-1'), isNull);
          expect(fetchCount, equals(0));

          // Network connection restores
          connectivity.setOnline(true);

          // Allow microtask turns for catch-up sync execution
          await Future<void>.delayed(const Duration(milliseconds: 50));

          // Missed message is reconciled into local Hive CE store
          expect(fetchCount, equals(1));
          final localMsg = messagesStore.getMessage('msg-missed-offline-1');
          expect(localMsg, isNotNull);
          expect(localMsg!.text, equals('Message while you were offline'));
          expect(localMsg.deliveryState, equals(DeliveryState.sent));

          // Cursor was committed
          final cursor = syncCursorsStore.getCursor('messages_$accountId');
          expect(cursor, isNotNull);
          expect(
            cursor!.lastSyncTimestamp,
            equals(missedSentAt.microsecondsSinceEpoch),
          );
          expect(cursor.lastSyncId, equals('msg-missed-offline-1'));

          await service.stop();
        },
      );

      test(
        'Realtime initial subscription and subsequent reconnection trigger catch-up sync',
        () async {
          int syncInvocations = 0;
          final service = ReconciliationService(
            accountId: accountId,
            messagesStore: messagesStore,
            chatsStore: chatsStore,
            syncCursorsStore: syncCursorsStore,
            connectivityService: connectivity,
            defaultFetcher: (after, lastId, limit) async {
              syncInvocations++;
              return [];
            },
          );

          await service.startRealtime();

          // 1. Initial subscription confirmed
          service.handleRealtimeStatus(RealtimeSubscribeStatus.subscribed);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(syncInvocations, equals(1));

          // 2. Subsequent reconnect (e.g. after channel re-established)
          service.handleRealtimeStatus(RealtimeSubscribeStatus.subscribed);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(syncInvocations, equals(2));

          await service.stop();
        },
      );

      test(
        'concurrent sync calls are strictly serialized without overlapping executions',
        () async {
          int concurrentExecutions = 0;
          int maxConcurrentObserved = 0;
          int completedRuns = 0;

          final service = ReconciliationService(
            accountId: accountId,
            messagesStore: messagesStore,
            chatsStore: chatsStore,
            syncCursorsStore: syncCursorsStore,
          );

          Future<List<Map<String, dynamic>>> delayedFetcher(
            DateTime after,
            String? lastId,
            int limit,
          ) async {
            concurrentExecutions++;
            if (concurrentExecutions > maxConcurrentObserved) {
              maxConcurrentObserved = concurrentExecutions;
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
            concurrentExecutions--;
            completedRuns++;
            return [];
          }

          // Fire 3 simultaneous sync calls
          final future1 = service.syncMessages(customFetcher: delayedFetcher);
          final future2 = service.syncMessages(customFetcher: delayedFetcher);
          final future3 = service.syncMessages(customFetcher: delayedFetcher);

          await Future.wait([future1, future2, future3]);

          // Max concurrency must strictly be 1 (never overlapped)
          expect(maxConcurrentObserved, equals(1));
          expect(completedRuns, equals(3));

          await service.stop();
        },
      );

      test(
        'duplicate delivery via Realtime and catch-up sync merges idempotently',
        () async {
          const msgId = 'msg-duplicate-stream-sync-1';
          final sentAt = DateTime.utc(2026, 10, 24, 14, 15, 0);

          final remoteRow = {
            'id': msgId,
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Concurrent stream and catch-up item',
            'type': 'text',
            'status': 1,
            'sent_at': sentAt.toIso8601String(),
          };

          final service = ReconciliationService(
            accountId: accountId,
            messagesStore: messagesStore,
            chatsStore: chatsStore,
            syncCursorsStore: syncCursorsStore,
            defaultFetcher: (after, lastId, limit) async => [remoteRow],
          );

          // 1. Message arrives via Realtime event
          await service.reconcileRemoteMessage(remoteRow);
          expect(messagesStore.getMessage(msgId), isNotNull);
          expect(messagesStore.getMessagesForChat(chatId).length, equals(1));

          // 2. Same message arrives via Catch-Up Sync
          await service.syncMessages();

          // Must still have exactly 1 record in local store (no duplicates)
          expect(messagesStore.getMessagesForChat(chatId).length, equals(1));
          final record = messagesStore.getMessage(msgId)!;
          expect(record.text, equals('Concurrent stream and catch-up item'));
          expect(record.deliveryState, equals(DeliveryState.sent));

          await service.stop();
        },
      );

      test(
        'closing database during catch-up stops cleanly without writing to closed boxes',
        () async {
          final syncStarted = Completer<void>();
          final finishSync = Completer<List<Map<String, dynamic>>>();

          final service = ReconciliationService(
            accountId: accountId,
            messagesStore: messagesStore,
            chatsStore: chatsStore,
            syncCursorsStore: syncCursorsStore,
          );

          final syncFuture = service.syncMessages(
            customFetcher: (after, lastId, limit) async {
              syncStarted.complete();
              return finishSync.future;
            },
          );

          await syncStarted.future;

          // Close the service and underlying Hive boxes
          await service.stop();
          await msgBox.close();
          await cursorBox.close();

          // Complete the network fetch after closure
          finishSync.complete([
            {
              'id': 'msg-late-closed-box',
              'chat_id': chatId,
              'sender_id': otherUserId,
              'text': 'Should not write to closed box',
              'type': 'text',
              'status': 1,
              'sent_at': DateTime.now().toUtc().toIso8601String(),
            },
          ]);

          final result = await syncFuture;
          expect(result, equals(0));
        },
      );
    },
  );
}
