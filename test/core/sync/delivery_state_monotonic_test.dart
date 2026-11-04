import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Monotonic Delivery-State Progression Tests (Fix 2)', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late MessagesStore store;

    const accountId = 'user-alice-monotonic-test';
    const chatId = 'chat-monotonic-test';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('delivery_monotonic_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      store = MessagesStore(msgBox);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'read followed by delayed sent update does NOT downgrade deliveryState',
      () async {
        final msg = ChatMessage(
          id: 'msg-read-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Message already read by peer',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.read,
        );

        await store.saveMessage(msg);
        expect(
          store.getMessage('msg-read-1')?.deliveryState,
          equals(DeliveryState.read),
        );

        // Delayed outbox completion or lagging status event tries to set sent
        await store.updateDelivery('msg-read-1', DeliveryState.sent);

        // Must remain read (never downgrade)
        final afterUpdate = store.getMessage('msg-read-1');
        expect(afterUpdate?.deliveryState, equals(DeliveryState.read));
      },
    );

    test(
      'delivered followed by delayed sent update does NOT downgrade deliveryState',
      () async {
        final msg = ChatMessage(
          id: 'msg-delivered-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Message already delivered to peer',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.delivered,
        );

        await store.saveMessage(msg);
        expect(
          store.getMessage('msg-delivered-1')?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // Delayed sent update arrives
        await store.updateDelivery('msg-delivered-1', DeliveryState.sent);

        // Must remain delivered
        final afterUpdate = store.getMessage('msg-delivered-1');
        expect(afterUpdate?.deliveryState, equals(DeliveryState.delivered));
      },
    );

    test(
      'repeated delivery and read confirmations are strictly idempotent',
      () async {
        final msg = ChatMessage(
          id: 'msg-repeated-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Repeated status confirmations',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sent,
        );

        await store.saveMessage(msg);

        // Multiple delivered confirmations
        await store.updateDelivery('msg-repeated-1', DeliveryState.delivered);
        await store.updateDelivery('msg-repeated-1', DeliveryState.delivered);
        expect(
          store.getMessage('msg-repeated-1')?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // Multiple read confirmations
        await store.updateDelivery('msg-repeated-1', DeliveryState.read);
        await store.updateDelivery('msg-repeated-1', DeliveryState.read);
        expect(
          store.getMessage('msg-repeated-1')?.deliveryState,
          equals(DeliveryState.read),
        );
      },
    );

    test(
      'out-of-order realtime updates advance state monotonically without regressions',
      () async {
        final msg = ChatMessage(
          id: 'msg-ooo-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Out of order update test',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await store.saveMessage(msg);

        // 1. Recipient fast acknowledgment sets delivered (2) before server ack arrives
        await store.updateDelivery('msg-ooo-1', DeliveryState.delivered);
        expect(
          store.getMessage('msg-ooo-1')?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // 2. Delayed server ack sent (1) arrives out of order
        await store.updateDelivery('msg-ooo-1', DeliveryState.sent);
        expect(
          store.getMessage('msg-ooo-1')?.deliveryState,
          equals(DeliveryState.delivered),
        );

        // 3. Read receipt (3) arrives
        await store.updateDelivery('msg-ooo-1', DeliveryState.read);
        expect(
          store.getMessage('msg-ooo-1')?.deliveryState,
          equals(DeliveryState.read),
        );

        // 4. Stale batch update with delivered (2) arrives late
        await store.updateDelivery('msg-ooo-1', DeliveryState.delivered);
        expect(
          store.getMessage('msg-ooo-1')?.deliveryState,
          equals(DeliveryState.read),
        );
      },
    );

    test(
      'failure handling after message has already been confirmed by the server is rejected',
      () async {
        final msg = ChatMessage(
          id: 'msg-confirmed-fail-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Confirmed message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sent,
        );

        await store.saveMessage(msg);

        // Delayed outbox failure or worker timeout attempts to mark message as failed
        await store.updateDelivery(
          'msg-confirmed-fail-1',
          DeliveryState.sending,
          failure: MessageFailureReason.serverFailed,
        );

        final state = store.getMessage('msg-confirmed-fail-1');
        // Must remain sent with failure == null (stronger evidence wins)
        expect(state?.deliveryState, equals(DeliveryState.sent));
        expect(state?.failure, isNull);
      },
    );

    test(
      'reconciliation of an optimistic local message with a remote row upgrades deliveryState and preserves fields',
      () async {
        final now = DateTime.now();
        final optimisticLocal = ChatMessage(
          id: 'msg-reconcile-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Optimistic text',
          sentAt: now,
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await store.saveMessage(optimisticLocal);

        // Remote row arrives from Supabase with status=1 (sent)
        final remoteRow = ChatMessage(
          id: 'msg-reconcile-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Optimistic text',
          sentAt: now,
          type: MessageType.text,
          deliveryState: DeliveryState.sent,
        );

        await store.saveMessage(remoteRow);

        final reconciled = store.getMessage('msg-reconcile-1');
        expect(reconciled, isNotNull);
        expect(reconciled!.deliveryState, equals(DeliveryState.sent));
        expect(reconciled.text, equals('Optimistic text'));
        expect(reconciled.failure, isNull);
      },
    );
  });
}
