import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';

void main() {
  group('Repository Migration & Local Hive CE Persistence Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late Box legacySummaryBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;

    const accountId = 'user-alice-repo-test';
    const chatId = 'chat-alice-bob';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('repo_migration_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      chatBox = await Hive.openBox('chats_cache_$accountId');
      legacySummaryBox = await Hive.openBox('chat_cache');

      messagesStore = MessagesStore(msgBox);
      chatsStore = ChatsStore(chatBox);
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
      'ChatsRepository with ChatsStore emits local cached summaries immediately (offline-first)',
      () async {
        final now = DateTime.now();
        final summary = ChatSummary(
          id: chatId,
          lastMessage: 'Cached offline message',
          lastTime: now,
          unread: 1,
          muted: false,
          otherUserId: 'user-bob',
          members: [accountId, 'user-bob'],
          lastSenderId: 'user-bob',
          lastMessageStatus: 1,
        );

        // Pre-populate local Hive CE store
        await chatsStore.saveChatSummary(summary);

        final repo = ChatsRepository(chatsStore: chatsStore);

        // watchLocalChats should immediately emit the local cached summary
        final localStream = repo.watchLocalChats();
        expect(localStream, isNotNull);

        final firstEmission = await localStream!.first;
        expect(firstEmission, hasLength(1));
        expect(firstEmission.first.id, equals(chatId));
        expect(
          firstEmission.first.lastMessage,
          equals('Cached offline message'),
        );
      },
    );

    test(
      'MessagesRepository with MessagesStore emits local messages and provides reactive local stream',
      () async {
        final now = DateTime.now();
        final msg1 = ChatMessage(
          id: 'msg-offline-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Hello from local storage',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg1);

        final repo = MessagesRepository(messagesStore: messagesStore);

        final localStream = repo.watchLocalMessages(chatId);
        expect(localStream, isNotNull);

        final firstBatch = await localStream!.first;
        expect(firstBatch, hasLength(1));
        expect(firstBatch.first.id, equals('msg-offline-1'));
        expect(firstBatch.first.text, equals('Hello from local storage'));
      },
    );

    test(
      'MessageCache interoperates seamlessly with ChatsStore when provided',
      () async {
        final cache = await MessageCache.open(
          uid: accountId,
          chatsStore: chatsStore,
        );

        final now = DateTime.now();
        final summary = ChatSummary(
          id: 'chat-interop',
          lastMessage: 'Interop message',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: 'user-bob',
          members: [accountId, 'user-bob'],
          lastSenderId: accountId,
          lastMessageStatus: 1,
        );

        // Save via MessageCache
        await cache.saveChatSummaries([summary]);

        // Verify it was persisted to ChatsStore ('chats_cache_$accountId')
        expect(chatsStore.getChatSummary('chat-interop'), isNotNull);
        expect(
          chatsStore.getChatSummary('chat-interop')?.lastMessage,
          equals('Interop message'),
        );

        // Verify reading via MessageCache.getCachedChatSummaries retrieves from ChatsStore
        final cached = await cache.getCachedChatSummaries();
        expect(cached, hasLength(1));
        expect(cached.first.id, equals('chat-interop'));

        // Verify legacy summaryBox also received the data for backward compatibility
        final legacyRaw = legacySummaryBox.get('summaries');
        expect(legacyRaw, isNotNull);
        expect((legacyRaw as List), hasLength(1));
      },
    );

    test(
      'promoteStatusBatch updates delivery states in MessagesStore',
      () async {
        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-to-deliver',
          chatId: chatId,
          senderId: 'user-bob',
          text: 'Waiting for delivery mark',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);
        expect(
          messagesStore.getMessage('msg-to-deliver')?.deliveryState,
          equals(DeliveryState.sent),
        );

        final repo = MessagesRepository(messagesStore: messagesStore);

        // Promote status in local store
        await repo.promoteStatusBatch(
          chatId: chatId,
          messageIds: ['msg-to-deliver'],
          newStatus: DeliveryState.delivered.index,
        );

        expect(
          messagesStore.getMessage('msg-to-deliver')?.deliveryState,
          equals(DeliveryState.delivered),
        );
      },
    );
  });
}
