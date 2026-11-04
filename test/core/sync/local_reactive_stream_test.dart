import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/chat_stream_controller.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.1 — Local Reactive Message Stream Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box metaBox;
    late MessagesStore messagesStore;
    late MessageCache messageCache;
    late OutboxService outboxService;
    late MessagesRepository chatRepository;

    const currentUserId = 'user-alice-reactive-test';
    const otherUserId = 'user-bob-reactive-test';
    const chatId = 'chat-reactive-test-123';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('local_stream_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$currentUserId');
      metaBox = await Hive.openBox('outbox_meta_$currentUserId');
      messagesStore = MessagesStore(msgBox);
      messageCache = await MessageCache.open(uid: currentUserId);
      outboxService = OutboxService(
        messageBox: msgBox,
        metaBox: metaBox,
        messageCache: messageCache,
      );
      chatRepository = MessagesRepository(messagesStore: messagesStore);
    });

    tearDown(() async {
      if (msgBox.isOpen) await msgBox.close();
      if (metaBox.isOpen) await metaBox.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'offline optimistic message appears immediately in active chat stream',
      () async {
        final streamCtrl = ChatStreamController(
          chatId: chatId,
          currentUserId: currentUserId,
          repo: chatRepository,
          outbox: outboxService,
          messagesStore: messagesStore,
        );

        final emissions = <List<ChatMessage>>[];
        final sub = streamCtrl.stream.listen(emissions.add);

        // Allow microtask to process initial empty emission
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Enqueue optimistic message locally (offline scenario)
        final optimisticMsg = ChatMessage(
          id: 'opt-msg-1',
          chatId: chatId,
          senderId: currentUserId,
          text: 'Hello from offline world!',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(optimisticMsg);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(emissions.isNotEmpty, isTrue);
        final latestList = emissions.last;
        expect(latestList.length, equals(1));
        expect(latestList.first.id, equals('opt-msg-1'));
        expect(latestList.first.text, equals('Hello from offline world!'));
        expect(latestList.first.deliveryState, equals(DeliveryState.sending));
        expect(latestList.first.isIncoming, isFalse);

        await sub.cancel();
        streamCtrl.dispose();
      },
    );

    test('local send-state changes propagate to the UI reactively', () async {
      final initialMsg = ChatMessage(
        id: 'msg-lifecycle-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Testing state transitions',
        sentAt: DateTime.now().toUtc(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
      );
      await messagesStore.saveMessage(initialMsg);

      final streamCtrl = ChatStreamController(
        chatId: chatId,
        currentUserId: currentUserId,
        repo: chatRepository,
        outbox: outboxService,
        messagesStore: messagesStore,
      );

      final emissions = <List<ChatMessage>>[];
      final sub = streamCtrl.stream.listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions.last.first.deliveryState, equals(DeliveryState.sending));

      // 1. Progress to sent
      await messagesStore.updateDelivery('msg-lifecycle-1', DeliveryState.sent);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last.first.deliveryState, equals(DeliveryState.sent));
      expect(emissions.last.first.failure, isNull);

      // 2. Simulate server failure on sending message
      final failedMsg = ChatMessage(
        id: 'msg-failed-1',
        chatId: chatId,
        senderId: currentUserId,
        text: 'Failed message',
        sentAt: DateTime.now().toUtc(),
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
      );
      await messagesStore.saveMessage(failedMsg);
      await messagesStore.updateDelivery(
        'msg-failed-1',
        DeliveryState.sending,
        failure: MessageFailureReason.serverFailed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final failedInStream = emissions.last.firstWhere(
        (m) => m.id == 'msg-failed-1',
      );
      expect(failedInStream.deliveryState, equals(DeliveryState.sending));
      expect(failedInStream.failure, equals(MessageFailureReason.serverFailed));
      expect(failedInStream.hasFailed, isTrue);

      // 3. Simulate retry (clear failure and stay in sending)
      await messagesStore.updateDelivery(
        'msg-failed-1',
        DeliveryState.sending,
        failure: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final retriedInStream = emissions.last.firstWhere(
        (m) => m.id == 'msg-failed-1',
      );
      expect(retriedInStream.deliveryState, equals(DeliveryState.sending));
      expect(retriedInStream.failure, isNull);
      expect(retriedInStream.hasFailed, isFalse);

      await sub.cancel();
      streamCtrl.dispose();
    });

    test(
      'message sorting orders confirmed chronologically and sending at end',
      () async {
        final t1 = DateTime.utc(2026, 10, 24, 10, 0, 0);
        final t2 = DateTime.utc(2026, 10, 24, 10, 5, 0);
        final t3 = DateTime.utc(2026, 10, 24, 10, 10, 0);

        // Prepopulate messages in scrambled order
        await messagesStore.saveMessage(
          ChatMessage(
            id: 'm-sent-2',
            chatId: chatId,
            senderId: otherUserId,
            text: 'Second message',
            sentAt: t2,
            deliveryState: DeliveryState.delivered,
            type: MessageType.text,
          ),
        );
        await messagesStore.saveMessage(
          ChatMessage(
            id: 'm-pending',
            chatId: chatId,
            senderId: currentUserId,
            text: 'Optimistic pending message',
            sentAt: t1, // Older timestamp, but sending state
            deliveryState: DeliveryState.sending,
            type: MessageType.text,
          ),
        );
        await messagesStore.saveMessage(
          ChatMessage(
            id: 'm-sent-1',
            chatId: chatId,
            senderId: currentUserId,
            text: 'First message',
            sentAt: t1,
            deliveryState: DeliveryState.sent,
            type: MessageType.text,
          ),
        );
        await messagesStore.saveMessage(
          ChatMessage(
            id: 'm-sent-3',
            chatId: chatId,
            senderId: otherUserId,
            text: 'Third message',
            sentAt: t3,
            deliveryState: DeliveryState.read,
            type: MessageType.text,
          ),
        );

        final streamCtrl = ChatStreamController(
          chatId: chatId,
          currentUserId: currentUserId,
          repo: chatRepository,
          outbox: outboxService,
          messagesStore: messagesStore,
        );

        final emissions = <List<ChatMessage>>[];
        final sub = streamCtrl.stream.listen(emissions.add);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        final list = emissions.last;
        expect(list.length, equals(4));

        // Confirmed messages ordered chronologically
        expect(list[0].id, equals('m-sent-1'));
        expect(list[1].id, equals('m-sent-2'));
        expect(list[2].id, equals('m-sent-3'));
        // Sending message ordered at end
        expect(list[3].id, equals('m-pending'));

        // Verify incoming flags
        expect(list[0].isIncoming, isFalse);
        expect(list[1].isIncoming, isTrue);
        expect(list[2].isIncoming, isTrue);
        expect(list[3].isIncoming, isFalse);

        await sub.cancel();
        streamCtrl.dispose();
      },
    );

    test('disposing ChatStreamController cancels subscription safely', () async {
      final streamCtrl = ChatStreamController(
        chatId: chatId,
        currentUserId: currentUserId,
        repo: chatRepository,
        outbox: outboxService,
        messagesStore: messagesStore,
      );

      final emissions = <List<ChatMessage>>[];
      streamCtrl.stream.listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final initialCount = emissions.length;

      streamCtrl.dispose();

      // Additional write after dispose must not throw or emit to closed stream
      await messagesStore.saveMessage(
        ChatMessage(
          id: 'after-dispose',
          chatId: chatId,
          senderId: currentUserId,
          text: 'After dispose',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emissions.length, equals(initialCount));
    });
  });
}
