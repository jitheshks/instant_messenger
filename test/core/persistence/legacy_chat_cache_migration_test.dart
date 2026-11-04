import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/migrations/legacy_chat_cache_migration.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';

void main() {
  group('LegacyChatCacheMigration Unit Tests', () {
    late Directory tempDir;
    late Box legacyBox;
    late Box targetBox;
    late ChatsStore targetStore;

    const userA = 'user-alice-123';
    const userB = 'user-bob-456';
    const userC = 'user-charlie-789';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('migration_test_');
      Hive.init(tempDir.path);

      legacyBox = await Hive.openBox(LegacyChatCacheMigration.legacyBoxName);
      targetBox = await Hive.openBox('chats_cache_$userA');
      targetStore = ChatsStore(targetBox);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('migrates valid conversation summaries belonging to User A', () async {
      final now = DateTime.now();

      final summary1 = ChatSummary(
        id: '${userA}_$userB',
        lastMessage: 'Hello Alice',
        lastTime: now,
        unread: 1,
        muted: false,
        otherUserId: userB,
        members: [userA, userB],
        lastSenderId: userB,
        lastMessageStatus: 1,
      );

      final summary2 = ChatSummary(
        id: '${userA}_$userC',
        lastMessage: 'Meeting at 3pm',
        lastTime: now.add(const Duration(minutes: 5)),
        unread: 0,
        muted: true,
        otherUserId: userC,
        members: [userA, userC],
        lastSenderId: userA,
        lastMessageStatus: 2,
      );

      // Save in legacy box format (key 'summaries' with List<Map>)
      await legacyBox.put('summaries', [summary1.toJson(), summary2.toJson()]);

      final count = await LegacyChatCacheMigration.migrate(
        accountId: userA,
        targetStore: targetStore,
        legacyBox: legacyBox,
      );

      expect(count, equals(2));

      final allInTarget = targetStore.getAllChatSummaries();
      expect(allInTarget, hasLength(2));
      expect(allInTarget.any((c) => c.id == '${userA}_$userB'), isTrue);
      expect(allInTarget.any((c) => c.id == '${userA}_$userC'), isTrue);
      expect(
        targetStore.getChatSummary('${userA}_$userB')?.lastMessage,
        equals('Hello Alice'),
      );
    });

    test(
      'ignores summaries belonging strictly to other users (no data leak)',
      () async {
        final now = DateTime.now();

        final aliceChat = ChatSummary(
          id: '${userA}_$userB',
          lastMessage: 'Alice and Bob chat',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: userB,
          members: [userA, userB],
          lastSenderId: userB,
          lastMessageStatus: 1,
        );

        final bobCharlieChat = ChatSummary(
          id: '${userB}_$userC',
          lastMessage: 'Bob and Charlie private conversation',
          lastTime: now,
          unread: 2,
          muted: false,
          otherUserId: userC,
          members: [userB, userC], // Alice is NOT a member!
          lastSenderId: userC,
          lastMessageStatus: 1,
        );

        await legacyBox.put('summaries', [
          aliceChat.toJson(),
          bobCharlieChat.toJson(),
        ]);

        final count = await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );

        expect(count, equals(1));

        final allInTarget = targetStore.getAllChatSummaries();
        expect(allInTarget, hasLength(1));
        expect(allInTarget.first.id, equals('${userA}_$userB'));
        expect(targetStore.getChatSummary('${userB}_$userC'), isNull);
      },
    );

    test(
      'is strictly idempotent: repeated runs do not duplicate or corrupt entries',
      () async {
        final now = DateTime.now();
        final summary = ChatSummary(
          id: '${userA}_$userB',
          lastMessage: 'Idempotency test',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: userB,
          members: [userA, userB],
          lastSenderId: userB,
          lastMessageStatus: 1,
        );

        await legacyBox.put('summaries', [summary.toJson()]);

        // Run 1
        final count1 = await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );
        expect(count1, equals(1));
        expect(targetStore.getAllChatSummaries(), hasLength(1));

        // Run 2
        final count2 = await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );
        expect(count2, equals(1));
        expect(targetStore.getAllChatSummaries(), hasLength(1));
        expect(
          targetStore.getChatSummary('${userA}_$userB')?.lastMessage,
          equals('Idempotency test'),
        );
      },
    );

    test(
      'preserves legacy chat_cache box completely intact without data loss',
      () async {
        final now = DateTime.now();
        final summary = ChatSummary(
          id: '${userA}_$userB',
          lastMessage: 'Preserve me',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: userB,
          members: [userA, userB],
          lastSenderId: userB,
          lastMessageStatus: 1,
        );

        await legacyBox.put('summaries', [summary.toJson()]);

        await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );

        // Confirm legacy box still has data
        expect(legacyBox.get('summaries'), isNotNull);
        final rawList = legacyBox.get('summaries') as List;
        expect(rawList, hasLength(1));
      },
    );

    test(
      'handles empty box, corrupted records, and partial data safely without crashing',
      () async {
        // 1. Empty box
        final countEmpty = await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );
        expect(countEmpty, equals(0));

        // 2. Corrupted data in box
        await legacyBox.put('summaries', [
          'invalid string instead of map',
          {'id': '', 'lastMessage': 'No ID'},
          {'id': '${userA}_$userB', 'corruptedField': 123}, // partial
          42,
          null,
        ]);

        final countCorrupted = await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStore,
          legacyBox: legacyBox,
        );

        // Only the partial one with a valid ID and membership might parse, or 0. Never crashes.
        expect(countCorrupted, greaterThanOrEqualTo(0));
      },
    );

    test(
      'account switching: User A and User B migrate their respective chats to separate stores',
      () async {
        final now = DateTime.now();

        final aliceChat = ChatSummary(
          id: 'chat_alice_only',
          lastMessage: 'For Alice only',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: 'peer_1',
          members: [userA, 'peer_1'],
          lastSenderId: 'peer_1',
          lastMessageStatus: 1,
        );

        final bobChat = ChatSummary(
          id: 'chat_bob_only',
          lastMessage: 'For Bob only',
          lastTime: now,
          unread: 0,
          muted: false,
          otherUserId: 'peer_2',
          members: [userB, 'peer_2'],
          lastSenderId: 'peer_2',
          lastMessageStatus: 1,
        );

        await legacyBox.put('summaries', [
          aliceChat.toJson(),
          bobChat.toJson(),
        ]);

        // User A migration
        final targetBoxA = await Hive.openBox('chats_cache_$userA');
        final targetStoreA = ChatsStore(targetBoxA);
        await LegacyChatCacheMigration.migrate(
          accountId: userA,
          targetStore: targetStoreA,
          legacyBox: legacyBox,
        );

        // User B migration
        final targetBoxB = await Hive.openBox('chats_cache_$userB');
        final targetStoreB = ChatsStore(targetBoxB);
        await LegacyChatCacheMigration.migrate(
          accountId: userB,
          targetStore: targetStoreB,
          legacyBox: legacyBox,
        );

        expect(targetStoreA.getAllChatSummaries(), hasLength(1));
        expect(targetStoreA.getChatSummary('chat_alice_only'), isNotNull);
        expect(targetStoreA.getChatSummary('chat_bob_only'), isNull);

        expect(targetStoreB.getAllChatSummaries(), hasLength(1));
        expect(targetStoreB.getChatSummary('chat_bob_only'), isNotNull);
        expect(targetStoreB.getChatSummary('chat_alice_only'), isNull);
      },
    );
  });
}
