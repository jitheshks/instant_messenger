import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/sync_cursors_store.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.1 Hardened — Compound Cursor & Multi-Page Sync Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late Box cursorBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;
    late SyncCursorsStore syncCursorsStore;

    const accountId = 'user-alice-cursor-test';
    const otherUserId = 'user-bob-cursor-test';
    const chatId = 'chat-cursor-404';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('cursor_sync_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      chatBox = await Hive.openBox('chats_cache_$accountId');
      cursorBox = await Hive.openBox('sync_cursors_$accountId');

      messagesStore = MessagesStore(msgBox);
      chatsStore = ChatsStore(chatBox);
      syncCursorsStore = SyncCursorsStore(cursorBox);
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
      'incremental sync advances cursor only after local persistence succeeds',
      () async {
        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final t1 = DateTime.utc(2026, 10, 24, 14, 0, 0);
        final t2 = DateTime.utc(2026, 10, 24, 14, 5, 0);

        final batch = [
          {
            'id': 'msg-sync-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Batch 1 msg 1',
            'type': 'text',
            'status': 1,
            'sent_at': t1.toIso8601String(),
          },
          {
            'id': 'msg-sync-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Batch 1 msg 2',
            'type': 'text',
            'status': 1,
            'sent_at': t2.toIso8601String(),
          },
        ];

        final cursorKey = 'chat_messages_${accountId}_$chatId';
        expect(syncCursorsStore.getCursor(cursorKey), isNull);

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => batch,
        );

        expect(count, equals(2));
        expect(messagesStore.getMessage('msg-sync-1'), isNotNull);
        expect(messagesStore.getMessage('msg-sync-2'), isNotNull);

        final savedCursor = syncCursorsStore.getCursor(cursorKey);
        expect(savedCursor, isNotNull);
        expect(
          savedCursor!.lastSyncTimestamp,
          equals(t2.microsecondsSinceEpoch),
        );
        expect(savedCursor.lastSyncId, equals('msg-sync-2'));

        await service.stop();
      },
    );

    test('resumes from persisted cursor after app restart', () async {
      final t1 = DateTime.utc(2026, 10, 24, 14, 10, 0);
      final t2 = DateTime.utc(2026, 10, 24, 14, 20, 0);

      final cursorKey = 'chat_messages_${accountId}_$chatId';
      await syncCursorsStore.setCursor(
        cursorKey,
        t1.microsecondsSinceEpoch,
        syncId: 'msg-prior-1',
      );

      final service = ReconciliationService(
        accountId: accountId,
        messagesStore: messagesStore,
        chatsStore: chatsStore,
        syncCursorsStore: syncCursorsStore,
      );

      DateTime? requestedAfter;
      String? requestedLastId;

      final count = await service.syncMessages(
        chatId: chatId,
        batchSize: 10,
        customFetcher: (after, lastId, limit) async {
          requestedAfter = after;
          requestedLastId = lastId;
          return [
            {
              'id': 'msg-resumed-2',
              'chat_id': chatId,
              'sender_id': otherUserId,
              'text': 'Resumed message',
              'type': 'text',
              'status': 1,
              'sent_at': t2.toIso8601String(),
            },
          ];
        },
      );

      expect(count, equals(1));
      expect(requestedAfter, equals(t1));
      expect(requestedLastId, equals('msg-prior-1'));

      final updatedCursor = syncCursorsStore.getCursor(cursorKey);
      expect(
        updatedCursor!.lastSyncTimestamp,
        equals(t2.microsecondsSinceEpoch),
      );
      expect(updatedCursor.lastSyncId, equals('msg-resumed-2'));

      await service.stop();
    });

    test(
      'more records share the exact same timestamp than fit in one page (Task 1)',
      () async {
        final sameTime = DateTime.utc(2026, 10, 24, 15, 0, 0);

        // 4 records with identical timestamp
        final allRecords = [
          {
            'id': 'msg-col-01',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Message 01 at same time',
            'type': 'text',
            'status': 1,
            'sent_at': sameTime.toIso8601String(),
          },
          {
            'id': 'msg-col-02',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Message 02 at same time',
            'type': 'text',
            'status': 1,
            'sent_at': sameTime.toIso8601String(),
          },
          {
            'id': 'msg-col-03',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Message 03 at same time',
            'type': 'text',
            'status': 1,
            'sent_at': sameTime.toIso8601String(),
          },
          {
            'id': 'msg-col-04',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Message 04 at same time',
            'type': 'text',
            'status': 1,
            'sent_at': sameTime.toIso8601String(),
          },
        ];

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final cursorKey = 'chat_messages_${accountId}_$chatId';

        // Custom fetcher simulating compound PostgREST pagination:
        // (sent_at > after OR (sent_at == after AND id > lastId)) ORDER BY sent_at ASC, id ASC LIMIT batchSize
        final fetcherCallLog = <String?>[];
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize:
              2, // Small batch size to force multiple pages with identical timestamps
          customFetcher: (after, lastId, limit) async {
            fetcherCallLog.add(lastId);

            final matching = allRecords.where((r) {
              final rTime = DateTime.parse(r['sent_at'] as String);
              final rId = r['id'] as String;
              if (rTime.isAfter(after)) return true;
              if (rTime.isAtSameMomentAs(after)) {
                if (lastId == null || lastId.isEmpty) return true;
                return rId.compareTo(lastId) > 0;
              }
              return false;
            }).toList();

            return matching.take(limit).toList();
          },
        );

        // All 4 messages must be reconciled without starvation or regression
        expect(count, equals(4));
        expect(messagesStore.getMessage('msg-col-01'), isNotNull);
        expect(messagesStore.getMessage('msg-col-02'), isNotNull);
        expect(messagesStore.getMessage('msg-col-03'), isNotNull);
        expect(messagesStore.getMessage('msg-col-04'), isNotNull);

        // Verified multi-page pagination with compound cursor
        expect(fetcherCallLog, contains(null)); // Page 1 starts with null
        expect(
          fetcherCallLog,
          contains('msg-col-02'),
        ); // Page 2 starts after msg-col-02

        // Cursor committed to the last record
        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(
          finalCursor!.lastSyncTimestamp,
          equals(sameTime.microsecondsSinceEpoch),
        );
        expect(finalCursor.lastSyncId, equals('msg-col-04'));

        await service.stop();
      },
    );

    test(
      'multi-page backlog spanning at least 3 pages drains to completion (Task 3)',
      () async {
        final t0 = DateTime.utc(2026, 10, 24, 16, 0, 0);

        // 7 messages across time
        final allRecords = List.generate(7, (i) {
          final t = t0.add(Duration(minutes: i * 5));
          return {
            'id': 'msg-backlog-$i',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Backlog message #$i',
            'type': 'text',
            'status': 1,
            'sent_at': t.toIso8601String(),
          };
        });

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final cursorKey = 'chat_messages_${accountId}_$chatId';

        // Batch size = 2 -> Requires 4 pages (2 + 2 + 2 + 1)
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            final matching = allRecords.where((r) {
              final rTime = DateTime.parse(r['sent_at'] as String);
              final rId = r['id'] as String;
              if (rTime.isAfter(after)) return true;
              if (rTime.isAtSameMomentAs(after)) {
                if (lastId == null || lastId.isEmpty) return true;
                return rId.compareTo(lastId) > 0;
              }
              return false;
            }).toList();

            return matching.take(limit).toList();
          },
        );

        // All 7 messages successfully drained
        expect(count, equals(7));
        for (int i = 0; i < 7; i++) {
          expect(messagesStore.getMessage('msg-backlog-$i'), isNotNull);
        }

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(finalCursor!.lastSyncId, equals('msg-backlog-6'));

        await service.stop();
      },
    );

    test(
      'failure in later page preserves previously committed progress (Task 3)',
      () async {
        final t0 = DateTime.utc(2026, 10, 24, 17, 0, 0);

        final page1 = [
          {
            'id': 'msg-failtest-0',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 1 item 0',
            'type': 'text',
            'status': 1,
            'sent_at': t0.toIso8601String(),
          },
          {
            'id': 'msg-failtest-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 1 item 1',
            'type': 'text',
            'status': 1,
            'sent_at': t0.add(const Duration(minutes: 1)).toIso8601String(),
          },
        ];

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final cursorKey = 'chat_messages_${accountId}_$chatId';
        int pageCalls = 0;

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            pageCalls++;
            if (pageCalls == 1) return page1;
            throw SocketException('Network failed during page 2');
          },
        );

        // Page 1 succeeded and committed
        expect(count, equals(2));
        expect(messagesStore.getMessage('msg-failtest-0'), isNotNull);
        expect(messagesStore.getMessage('msg-failtest-1'), isNotNull);

        // Cursor is safely committed at end of Page 1
        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor, isNotNull);
        expect(cursor!.lastSyncId, equals('msg-failtest-1'));

        // Subsequent retry resumes from Page 1 cursor
        final page2 = [
          {
            'id': 'msg-failtest-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 2 item 2',
            'type': 'text',
            'status': 1,
            'sent_at': t0.add(const Duration(minutes: 2)).toIso8601String(),
          },
        ];

        final retryCount = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            expect(lastId, equals('msg-failtest-1'));
            return page2;
          },
        );

        expect(retryCount, equals(1));
        expect(messagesStore.getMessage('msg-failtest-2'), isNotNull);

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(finalCursor!.lastSyncId, equals('msg-failtest-2'));

        await service.stop();
      },
    );

    test(
      'safety limit caps max pages to prevent runaway sync (Task 3)',
      () async {
        final t0 = DateTime.utc(2026, 10, 24, 18, 0, 0);

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        int pagesQueried = 0;
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          maxPages: 2, // Strict safety limit: 2 pages max
          customFetcher: (after, lastId, limit) async {
            pagesQueried++;
            return [
              {
                'id': 'msg-runaway-$pagesQueried-1',
                'chat_id': chatId,
                'sender_id': otherUserId,
                'text': 'Item 1',
                'type': 'text',
                'status': 1,
                'sent_at': t0
                    .add(Duration(minutes: pagesQueried * 2))
                    .toIso8601String(),
              },
              {
                'id': 'msg-runaway-$pagesQueried-2',
                'chat_id': chatId,
                'sender_id': otherUserId,
                'text': 'Item 2',
                'type': 'text',
                'status': 1,
                'sent_at': t0
                    .add(Duration(minutes: pagesQueried * 2 + 1))
                    .toIso8601String(),
              },
            ];
          },
        );

        // Exactly 2 pages * 2 items = 4 synced
        expect(pagesQueried, equals(2));
        expect(count, equals(4));

        await service.stop();
      },
    );

    test(
      'page that fails to advance cursor breaks to prevent infinite loop (Task 3)',
      () async {
        final t0 = DateTime.utc(2026, 10, 24, 19, 0, 0);

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        // Set initial cursor
        final cursorKey = 'chat_messages_${accountId}_$chatId';
        await syncCursorsStore.setCursor(
          cursorKey,
          t0.microsecondsSinceEpoch,
          syncId: 'msg-static',
        );

        int calls = 0;
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            calls++;
            // Returns rows that are NOT after the cursor
            return [
              {
                'id': 'msg-static',
                'chat_id': chatId,
                'sender_id': otherUserId,
                'text': 'Static item',
                'type': 'text',
                'status': 1,
                'sent_at': t0.toIso8601String(),
              },
            ];
          },
        );

        // Loop terminates immediately on zero progress
        expect(calls, equals(1));
        expect(count, equals(0));

        await service.stop();
      },
    );
  });
}
