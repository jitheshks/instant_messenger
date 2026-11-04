import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.2 — Remote-to-Local ReconciliationService Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late Box outboxBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;
    late OutboxStore outboxStore;
    late ReconciliationService service;

    const accountId = 'user-alice-reconcile-test';
    const otherUserId = 'user-bob-reconcile-test';
    const chatId = 'chat-reconcile-101';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('reconcile_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      chatBox = await Hive.openBox('chats_cache_$accountId');
      outboxBox = await Hive.openBox('outbox_mutations_$accountId');

      messagesStore = MessagesStore(msgBox);
      chatsStore = ChatsStore(chatBox);
      outboxStore = OutboxStore(outboxBox);

      service = ReconciliationService(
        accountId: accountId,
        messagesStore: messagesStore,
        chatsStore: chatsStore,
      );
    });

    tearDown(() async {
      await service.stop();
      if (msgBox.isOpen) await msgBox.close();
      if (chatBox.isOpen) await chatBox.close();
      if (outboxBox.isOpen) await outboxBox.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'remote insert reconciles cleanly with an existing optimistic local message',
      () async {
        const msgId = 'msg-optimistic-merge-1';
        final sentAt = DateTime.utc(2026, 10, 24, 12, 0, 0);

        // 1. Optimistic message saved locally in sending state
        final localOptimistic = ChatMessage(
          id: msgId,
          chatId: chatId,
          senderId: accountId,
          text: 'Sending this message now',
          sentAt: sentAt,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );
        await messagesStore.saveMessage(localOptimistic);

        expect(
          messagesStore.getMessage(msgId)?.deliveryState,
          equals(DeliveryState.sending),
        );

        // 2. Remote confirmation row arrives via Realtime with status 1 (sent)
        final remoteRow = {
          'id': msgId,
          'chat_id': chatId,
          'sender_id': accountId,
          'text': 'Sending this message now',
          'type': 'text',
          'status': 1, // sent
          'sent_at': sentAt.toIso8601String(),
        };

        final events = <ReconciliationEvent>[];
        final sub = service.events.listen(events.add);

        await service.reconcileRemoteMessage(remoteRow);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // 3. Merges into canonical record with deliveryState upgraded to sent
        final canonical = messagesStore.getMessage(msgId);
        expect(canonical, isNotNull);
        expect(canonical!.deliveryState, equals(DeliveryState.sent));
        expect(canonical.text, equals('Sending this message now'));
        expect(canonical.isIncoming, isFalse);

        expect(events.length, equals(1));
        expect(events.first.type, equals(ReconciliationEventType.updated));
        expect(events.first.messageId, equals(msgId));

        await sub.cancel();
      },
    );

    test(
      'duplicate and out-of-order Realtime events are handled idempotently',
      () async {
        const msgId = 'msg-idempotent-stream-1';
        final sentAt = DateTime.utc(2026, 10, 24, 12, 10, 0);

        final remoteRowDelivered = {
          'id': msgId,
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Hello peer',
          'type': 'text',
          'status': 2, // delivered
          'sent_at': sentAt.toIso8601String(),
        };

        // First delivery event
        await service.reconcileRemoteMessage(remoteRowDelivered);
        expect(
          messagesStore.getMessage(msgId)?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // Duplicate delivery event
        await service.reconcileRemoteMessage(remoteRowDelivered);
        expect(
          messagesStore.getMessage(msgId)?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // Stale out-of-order 'sent' event arriving late
        final remoteRowSent = {
          'id': msgId,
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Hello peer',
          'type': 'text',
          'status': 1, // sent (stale)
          'sent_at': sentAt.toIso8601String(),
        };

        await service.reconcileRemoteMessage(remoteRowSent);

        // State MUST remain delivered; never downgrade to sent
        expect(
          messagesStore.getMessage(msgId)?.deliveryState,
          equals(DeliveryState.delivered),
        );
      },
    );

    test(
      'stale remote record cannot downgrade locally confirmed read state',
      () async {
        const msgId = 'msg-read-guard-1';
        final sentAt = DateTime.utc(2026, 10, 24, 12, 15, 0);

        // Local state already updated to 'read' (status 3) by peer read receipt
        final readLocal = ChatMessage(
          id: msgId,
          chatId: chatId,
          senderId: accountId,
          text: 'Have you seen this?',
          sentAt: sentAt,
          deliveryState: DeliveryState.read,
          type: MessageType.text,
        );
        await messagesStore.saveMessage(readLocal);

        // Incoming lagging remote event reporting status 1 (sent)
        final laggingRow = {
          'id': msgId,
          'chat_id': chatId,
          'sender_id': accountId,
          'text': 'Have you seen this?',
          'type': 'text',
          'status': 1,
          'sent_at': sentAt.toIso8601String(),
        };

        await service.reconcileRemoteMessage(laggingRow);

        final result = messagesStore.getMessage(msgId);
        expect(result!.deliveryState, equals(DeliveryState.read));
      },
    );

    test(
      'locally queued unrelated messages remain untouched during reconciliation',
      () async {
        // Unrelated queued message
        final queuedMsg = ChatMessage(
          id: 'msg-queued-offline-1',
          chatId: 'other-chat-999',
          senderId: accountId,
          text: 'Offline pending message',
          sentAt: DateTime.utc(2026, 10, 24, 12, 20, 0),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );
        await messagesStore.saveMessage(queuedMsg);

        // Remote row for another message arrives
        final incomingRow = {
          'id': 'msg-incoming-remote-2',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'New incoming from Bob',
          'type': 'text',
          'status': 1,
          'sent_at': DateTime.utc(2026, 10, 24, 12, 21, 0).toIso8601String(),
        };

        await service.reconcileRemoteMessage(incomingRow);

        // Queued message is strictly preserved
        final untouched = messagesStore.getMessage('msg-queued-offline-1');
        expect(untouched, isNotNull);
        expect(untouched!.deliveryState, equals(DeliveryState.sending));

        // Reconciled message is inserted
        final incoming = messagesStore.getMessage('msg-incoming-remote-2');
        expect(incoming, isNotNull);
        expect(incoming!.text, equals('New incoming from Bob'));
        expect(incoming.isIncoming, isTrue);
      },
    );

    test(
      'reconciliation notifies OutboxDaemon to clean up confirmed mutation',
      () async {
        const msgId = 'msg-outbox-cleanup-1';

        // Enqueue mutation in outbox store
        await outboxStore.enqueue(
          OutboxEntry(
            id: msgId,
            accountId: accountId,
            mutationType: 'send_message',
            targetId: msgId,
            payloadJson: '{}',
            createdAt: DateTime.now(),
            nextAttemptAt: DateTime.now(),
          ),
        );
        expect(outboxStore.getById(msgId), isNotNull);

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
        );

        final serviceWithDaemon = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          outboxDaemon: daemon,
        );

        // Reconcile server confirmation (status 1)
        await serviceWithDaemon.reconcileRemoteMessage({
          'id': msgId,
          'chat_id': chatId,
          'sender_id': accountId,
          'text': 'Outbox confirm test',
          'type': 'text',
          'status': 1,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        });

        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Mutation removed from outbox
        expect(outboxStore.getById(msgId), isNull);

        await serviceWithDaemon.stop();
      },
    );

    test('reconciliation updates ChatsStore summary last message', () async {
      final initialTime = DateTime.utc(2026, 10, 24, 11, 0, 0);
      final chatSummary = ChatSummary(
        id: chatId,
        otherUserId: otherUserId,
        lastMessage: 'Old message',
        lastTime: initialTime,
        unread: 0,
        muted: false,
        members: [accountId, otherUserId],
        lastSenderId: otherUserId,
        lastMessageStatus: 1,
      );
      await chatsStore.saveChatSummary(chatSummary);

      final newerTime = DateTime.utc(2026, 10, 24, 12, 30, 0);
      await service.reconcileRemoteMessage({
        'id': 'msg-new-summary-1',
        'chat_id': chatId,
        'sender_id': otherUserId,
        'text': 'Latest updated message',
        'type': 'text',
        'status': 1,
        'sent_at': newerTime.toIso8601String(),
      });

      final updatedSummary = chatsStore.getChatSummary(chatId);
      expect(updatedSummary, isNotNull);
      expect(updatedSummary!.lastMessage, equals('Latest updated message'));
      expect(updatedSummary.lastTime, equals(newerTime));
      expect(updatedSummary.lastSenderId, equals(otherUserId));
    });
  });
}
