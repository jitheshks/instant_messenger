import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account Lifecycle & Multi-Account Isolation Tests', () {
    late Directory tempDir;
    final manager = HiveDatabaseManager.instance;

    const userAlice = 'user-alice-uuid-001';
    const userBob = 'user-bob-uuid-002';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('account_lifecycle_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
      await manager.closeCurrentAccount();
    });

    tearDown(() async {
      await manager.closeCurrentAccount();
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'User A -> logout -> User B isolation guarantees zero cross-account leakage',
      () async {
        final now = DateTime.now();

        // 1. Alice logs in
        final aliceDb = await manager.openAccount(userAlice);
        expect(manager.hasActiveDatabase, isTrue);
        expect(manager.activeDatabase?.accountId, equals(userAlice));

        // Alice writes private message and chat summary
        final aliceMsg = ChatMessage(
          id: 'msg-alice-secret',
          chatId: 'chat-alice-peer',
          senderId: userAlice,
          text: 'Top secret for Alice only',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );
        await aliceDb.messagesStore.saveMessage(aliceMsg);

        final aliceSummary = ChatSummary(
          id: 'chat-alice-peer',
          lastMessage: 'Top secret for Alice only',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: 'peer-99',
          members: [userAlice, 'peer-99'],
          lastSenderId: userAlice,
          lastMessageStatus: 1,
        );
        await aliceDb.chatsStore.saveChatSummary(aliceSummary);

        expect(aliceDb.messagesStore.getMessage('msg-alice-secret'), isNotNull);
        expect(aliceDb.chatsStore.getChatSummary('chat-alice-peer'), isNotNull);

        // 2. Alice logs out (closeCurrentAccount)
        await manager.closeCurrentAccount();
        expect(manager.hasActiveDatabase, isFalse);

        // 3. Bob logs in on same device
        final bobDb = await manager.openAccount(userBob);
        expect(manager.activeDatabase?.accountId, equals(userBob));

        // Verify Bob sees NONE of Alice's data
        expect(bobDb.messagesStore.getMessage('msg-alice-secret'), isNull);
        expect(bobDb.chatsStore.getChatSummary('chat-alice-peer'), isNull);
        expect(bobDb.chatsStore.getAllChatSummaries(), isEmpty);

        // Bob writes his own data
        final bobMsg = ChatMessage(
          id: 'msg-bob-hello',
          chatId: 'chat-bob-peer',
          senderId: userBob,
          text: 'Hello from Bob',
          sentAt: now,
          deliveryState: DeliveryState.sent,
          type: MessageType.text,
        );
        await bobDb.messagesStore.saveMessage(bobMsg);

        // 4. Bob logs out
        await manager.closeCurrentAccount();

        // 5. Alice logs back in: Alice's data was preserved offline!
        final aliceDb2 = await manager.openAccount(userAlice);
        expect(
          aliceDb2.messagesStore.getMessage('msg-alice-secret'),
          isNotNull,
        );
        expect(
          aliceDb2.messagesStore.getMessage('msg-alice-secret')?.text,
          equals('Top secret for Alice only'),
        );
        expect(
          aliceDb2.chatsStore.getChatSummary('chat-alice-peer'),
          isNotNull,
        );

        // And Alice cannot see Bob's data
        expect(aliceDb2.messagesStore.getMessage('msg-bob-hello'), isNull);
      },
    );

    test(
      'reopening account recovers abandoned in-flight outbox mutations',
      () async {
        final now = DateTime.now();

        // 1. Open account and enqueue an in-flight mutation
        final db1 = await manager.openAccount(userAlice);
        final abandonedMutation = OutboxEntry(
          id: 'mut-interrupted',
          accountId: userAlice,
          mutationType: 'send_message',
          targetId: 'msg-interrupted',
          payloadJson: '{"text": "interrupted"}',
          createdAt: now.subtract(const Duration(minutes: 5)),
          retryCount: 1,
          nextAttemptAt: now,
          state: 'in_flight',
        );
        await db1.outboxStore.enqueue(abandonedMutation);

        // 2. App process crashes / closes abruptly
        await manager.closeCurrentAccount();

        // 3. Reopening account runs crash recovery
        final db2 = await manager.openAccount(userAlice);
        final recovered = db2.outboxStore.getById('mut-interrupted');
        expect(recovered, isNotNull);
        expect(recovered!.state, equals('queued'));
        expect(recovered.retryCount, equals(1));
      },
    );

    test(
      'repeated openAccount calls for same user return existing active instance',
      () async {
        final db1 = await manager.openAccount(userAlice);
        final db2 = await manager.openAccount(userAlice);

        expect(identical(db1, db2), isTrue);
      },
    );
  });
}
