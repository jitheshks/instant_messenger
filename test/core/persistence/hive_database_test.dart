import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/persistence.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HiveDatabase & Hive CE Persistence Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('hive_db_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
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
      'account isolation guarantees User A data is not visible to User B',
      () async {
        final aliceDb = await HiveDatabase.openForAccount('alice-uuid');
        final bobDb = await HiveDatabase.openForAccount('bob-uuid');

        final now = DateTime.now();
        final msg = ChatMessage(
          id: 'msg-alice-1',
          chatId: 'chat-alice-bob',
          senderId: 'alice-uuid',
          text: 'Private message for Alice only',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );

        await aliceDb.messagesStore.saveMessage(msg);
        await aliceDb.chatsStore.saveChatSummary(
          ChatSummary(
            id: 'chat-alice-bob',
            lastMessage: 'Private message for Alice only',
            lastTime: now,
            unread: 0,
            muted: false,
            otherUserId: 'bob-uuid',
            members: const ['alice-uuid', 'bob-uuid'],
            lastSenderId: 'alice-uuid',
            lastMessageStatus: 1,
          ),
        );

        // Verify Alice has data
        expect(aliceDb.messagesStore.getMessage('msg-alice-1'), isNotNull);
        expect(aliceDb.chatsStore.getChatSummary('chat-alice-bob'), isNotNull);

        // Verify Bob's database has ZERO data from Alice
        expect(bobDb.messagesStore.getMessage('msg-alice-1'), isNull);
        expect(
          bobDb.messagesStore.getMessagesForChat('chat-alice-bob'),
          isEmpty,
        );
        expect(bobDb.chatsStore.getChatSummary('chat-alice-bob'), isNull);
        expect(bobDb.chatsStore.getAllChatSummaries(), isEmpty);

        await aliceDb.close();
        await bobDb.close();
      },
    );

    test('persistence is preserved across box close and reopen', () async {
      final db1 = await HiveDatabase.openForAccount('persist-uid');
      final now = DateTime.now();

      // 1. Message
      final msg = ChatMessage(
        id: 'msg-persist-1',
        chatId: 'chat-persist',
        senderId: 'persist-uid',
        text: 'Durable message content',
        sentAt: now,
        deliveryState: DeliveryState.sending,
        type: MessageType.text,
      );
      await db1.messagesStore.saveMessage(msg);

      // 2. Chat summary
      final chat = ChatSummary(
        id: 'chat-persist',
        lastMessage: 'Durable message content',
        lastTime: now,
        unread: 1,
        muted: false,
        otherUserId: 'peer-uid',
        members: const ['persist-uid', 'peer-uid'],
        lastSenderId: 'persist-uid',
        lastMessageStatus: 0,
      );
      await db1.chatsStore.saveChatSummary(chat);

      // 3. Outbox
      final outbox = OutboxEntry(
        id: 'outbox-mutation-1',
        accountId: 'persist-uid',
        mutationType: 'send_message',
        targetId: 'msg-persist-1',
        payloadJson: '{"text":"Durable message content"}',
        createdAt: now,
        nextAttemptAt: now.add(const Duration(seconds: 5)),
      );
      await db1.outboxStore.enqueue(outbox);

      // 4. Sync cursor
      await db1.syncCursorsStore.setCursor(
        'chat_watermark',
        1700000000,
        syncId: 'sync-123',
      );

      // 5. Attachment
      final attachment = AttachmentEntry(
        id: 'att-1',
        messageId: 'msg-persist-1',
        localPath: '/sandbox/att-1.png',
        mediaKind: MediaKind.image,
        mimeType: 'image/png',
        fileSizeBytes: 2048,
        createdAt: now,
      );
      await db1.attachmentsStore.saveAttachment(attachment);

      // Close database completely
      await db1.close();

      // Reopen database for the same account
      final db2 = await HiveDatabase.openForAccount('persist-uid');

      // Verify all 5 stores preserved every record
      final loadedMsg = db2.messagesStore.getMessage('msg-persist-1');
      expect(loadedMsg, isNotNull);
      expect(loadedMsg!.text, 'Durable message content');
      expect(loadedMsg.deliveryState, DeliveryState.sending);

      final loadedChat = db2.chatsStore.getChatSummary('chat-persist');
      expect(loadedChat, isNotNull);
      expect(loadedChat!.lastMessage, 'Durable message content');

      final loadedOutbox = db2.outboxStore.getById('outbox-mutation-1');
      expect(loadedOutbox, isNotNull);
      expect(loadedOutbox!.mutationType, 'send_message');
      expect(loadedOutbox.state, 'queued');

      final loadedCursor = db2.syncCursorsStore.getCursor('chat_watermark');
      expect(loadedCursor, isNotNull);
      expect(loadedCursor!.lastSyncTimestamp, 1700000000);
      expect(loadedCursor.lastSyncId, 'sync-123');

      final loadedAtt = db2.attachmentsStore.getAttachment('att-1');
      expect(loadedAtt, isNotNull);
      expect(loadedAtt!.localPath, '/sandbox/att-1.png');
      expect(loadedAtt.mediaKind, MediaKind.image);

      await db2.close();
    });

    test('reactive streams emit updates when data is modified', () async {
      final db = await HiveDatabase.openForAccount('reactive-uid');
      const chatId = 'chat-reactive-1';
      final now = DateTime.now();

      final emittedMessages = <List<ChatMessage>>[];
      final msgSub = db.messagesStore
          .watchMessages(chatId)
          .listen(emittedMessages.add);

      final emittedChats = <List<ChatSummary>>[];
      final chatSub = db.chatsStore.watchChatSummaries().listen(
        emittedChats.add,
      );

      await pumpEventQueue();

      // Initial emissions
      expect(emittedMessages.length, 1);
      expect(emittedMessages.first, isEmpty);
      expect(emittedChats.length, 1);
      expect(emittedChats.first, isEmpty);

      // Add message
      await db.messagesStore.saveMessage(
        ChatMessage(
          id: 'msg-r-1',
          chatId: chatId,
          senderId: 'reactive-uid',
          text: 'Reactive ping',
          sentAt: now,
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        ),
      );

      // Add chat
      await db.chatsStore.saveChatSummary(
        ChatSummary(
          id: chatId,
          lastMessage: 'Reactive ping',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: 'peer',
          members: const ['reactive-uid', 'peer'],
          lastSenderId: 'reactive-uid',
          lastMessageStatus: 0,
        ),
      );

      await pumpEventQueue();

      expect(emittedMessages.last.length, 1);
      expect(emittedMessages.last.first.text, 'Reactive ping');
      expect(emittedChats.last.length, 1);
      expect(emittedChats.last.first.lastMessage, 'Reactive ping');

      await msgSub.cancel();
      await chatSub.cancel();
      await db.close();
    });

    test(
      'durable outbox retrieves scheduled mutations ordered by nextAttemptAt',
      () async {
        final db = await HiveDatabase.openForAccount('outbox-uid');
        final now = DateTime.now();

        // 1. Scheduled in future (not ready)
        await db.outboxStore.enqueue(
          OutboxEntry(
            id: 'mutation-future',
            accountId: 'outbox-uid',
            mutationType: 'send_message',
            targetId: 'msg-future',
            payloadJson: '{}',
            createdAt: now,
            nextAttemptAt: now.add(const Duration(minutes: 5)),
          ),
        );

        // 2. Ready mutation 1 (earlier)
        await db.outboxStore.enqueue(
          OutboxEntry(
            id: 'mutation-earlier',
            accountId: 'outbox-uid',
            mutationType: 'send_message',
            targetId: 'msg-earlier',
            payloadJson: '{}',
            createdAt: now,
            nextAttemptAt: now.subtract(const Duration(seconds: 10)),
          ),
        );

        // 3. Ready mutation 2 (later)
        await db.outboxStore.enqueue(
          OutboxEntry(
            id: 'mutation-later',
            accountId: 'outbox-uid',
            mutationType: 'send_message',
            targetId: 'msg-later',
            payloadJson: '{}',
            createdAt: now,
            nextAttemptAt: now.subtract(const Duration(seconds: 2)),
          ),
        );

        final scheduled = db.outboxStore.getScheduled(now);
        expect(scheduled.length, 2);
        expect(scheduled[0].id, 'mutation-earlier');
        expect(scheduled[1].id, 'mutation-later');

        // Update state to in_flight
        await db.outboxStore.updateState('mutation-earlier', 'in_flight');
        final scheduledAfterUpdate = db.outboxStore.getScheduled(now);
        expect(scheduledAfterUpdate.length, 1);
        expect(scheduledAfterUpdate[0].id, 'mutation-later');

        await db.close();
      },
    );

    test(
      'sync cursors store sets, gets, and deletes watermark checkpoints',
      () async {
        final db = await HiveDatabase.openForAccount('cursor-uid');

        await db.syncCursorsStore.setCursor(
          'chat_cursor_1',
          1705000000,
          syncId: 'tie-breaker-uuid',
        );

        final cursor = db.syncCursorsStore.getCursor('chat_cursor_1');
        expect(cursor, isNotNull);
        expect(cursor!.cursorKey, 'chat_cursor_1');
        expect(cursor.lastSyncTimestamp, 1705000000);
        expect(cursor.lastSyncId, 'tie-breaker-uuid');

        await db.syncCursorsStore.deleteCursor('chat_cursor_1');
        expect(db.syncCursorsStore.getCursor('chat_cursor_1'), isNull);

        await db.close();
      },
    );

    test('attachments store tracks upload progress and remote paths', () async {
      final db = await HiveDatabase.openForAccount('att-uid');
      final now = DateTime.now();

      final entry = AttachmentEntry(
        id: 'att-upload-1',
        messageId: 'msg-target-1',
        localPath: '/storage/voice.m4a',
        mediaKind: MediaKind.audio,
        mimeType: 'audio/m4a',
        fileSizeBytes: 4096,
        createdAt: now,
      );

      await db.attachmentsStore.saveAttachment(entry);

      // In progress
      await db.attachmentsStore.updateUploadProgress(
        'att-upload-1',
        0.5,
        uploadStatus: 'uploading',
      );
      var current = db.attachmentsStore.getAttachment('att-upload-1');
      expect(current!.uploadProgress, 0.5);
      expect(current.uploadStatus, 'uploading');

      // Completed with remote path
      await db.attachmentsStore.updateUploadProgress(
        'att-upload-1',
        1.0,
        uploadStatus: 'completed',
        remotePath: 'chat_attachments/voice_1.m4a',
      );
      current = db.attachmentsStore.getAttachment('att-upload-1');
      expect(current!.uploadProgress, 1.0);
      expect(current.uploadStatus, 'completed');
      expect(current.remotePath, 'chat_attachments/voice_1.m4a');

      await db.close();
    });

    test(
      'interoperates seamlessly with legacy MessageCache box name and data format',
      () async {
        const uid = 'interop-user-1';
        final db = await HiveDatabase.openForAccount(uid);
        final now = DateTime.now();

        // Write via MessagesStore
        final msg = ChatMessage(
          id: 'interop-msg-1',
          chatId: 'interop-chat',
          senderId: uid,
          text: 'Written via MessagesStore',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );
        await db.messagesStore.saveMessage(msg);
        await db.close();

        // Read via MessageCache.open(uid)
        final legacyCache = await MessageCache.open(uid: uid);
        final recent = legacyCache.getRecent('interop-chat');

        expect(recent.length, 1);
        expect(recent.first.id, 'interop-msg-1');
        expect(recent.first.text, 'Written via MessagesStore');
        expect(recent.first.deliveryState, DeliveryState.sent);
      },
    );
  });
}
