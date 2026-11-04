import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/models/sync_cursor.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/sync_cursors_store.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.2 — Cursor Precision & Pagination Regression Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box chatBox;
    late Box cursorBox;
    late MessagesStore messagesStore;
    late ChatsStore chatsStore;
    late SyncCursorsStore syncCursorsStore;

    const accountId = 'user-alice-reg-test';
    const otherUserId = 'user-bob-reg-test';
    const chatId = 'chat-precision-402';
    final cursorKey = 'chat_messages_${accountId}_$chatId';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('cursor_precision_test_');
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

    // -------------------------------------------------------------------------
    // Test 1: Distinct microsecond timestamps within one millisecond
    // -------------------------------------------------------------------------
    test(
      'Test 1: Distinct microsecond timestamps within one millisecond retain correct order and precision',
      () async {
        final t1Str = '2026-10-23T10:00:00.123100Z';
        final t2Str = '2026-10-23T10:00:00.123456Z';
        final t3Str = '2026-10-23T10:00:00.123999Z';

        final dt1 = DateTime.parse(t1Str);
        final dt2 = DateTime.parse(t2Str);
        final dt3 = DateTime.parse(t3Str);

        // Verify that parsing preserves microsecond differences and does not collapse to same millisecond
        expect(
          dt1.microsecondsSinceEpoch,
          isNot(equals(dt2.microsecondsSinceEpoch)),
        );
        expect(
          dt2.microsecondsSinceEpoch,
          isNot(equals(dt3.microsecondsSinceEpoch)),
        );
        expect(
          dt1.millisecondsSinceEpoch,
          equals(dt2.millisecondsSinceEpoch),
        ); // Collapsed in ms!
        expect(
          dt2.millisecondsSinceEpoch,
          equals(dt3.millisecondsSinceEpoch),
        ); // Collapsed in ms!

        final batch = [
          {
            'id': 'msg-micro-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Micro 1',
            'type': 'text',
            'status': 1,
            'sent_at': t1Str,
          },
          {
            'id': 'msg-micro-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Micro 2',
            'type': 'text',
            'status': 1,
            'sent_at': t2Str,
          },
          {
            'id': 'msg-micro-3',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Micro 3',
            'type': 'text',
            'status': 1,
            'sent_at': t3Str,
          },
        ];

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => batch,
        );

        expect(count, equals(3));
        final savedCursor = syncCursorsStore.getCursor(cursorKey);
        expect(savedCursor, isNotNull);
        expect(
          savedCursor!.lastSyncTimestamp,
          equals(dt3.microsecondsSinceEpoch),
        );
        expect(savedCursor.lastSyncId, equals('msg-micro-3'));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 2: Timestamp ordering takes precedence over ID ordering
    // -------------------------------------------------------------------------
    test(
      'Test 2: Timestamp ordering takes precedence over ID ordering',
      () async {
        final tEarly = '2026-10-23T10:00:00.100000Z';
        final tLate = '2026-10-23T10:00:00.200000Z';

        final rowA = {
          'id': 'ZZZ-999',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Early time, late ID',
          'type': 'text',
          'status': 1,
          'sent_at': tEarly,
        };
        final rowB = {
          'id': 'AAA-001',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Late time, early ID',
          'type': 'text',
          'status': 1,
          'sent_at': tLate,
        };
        final rowC = {
          'id': 'BBB-002',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Late time, tie-breaker ID',
          'type': 'text',
          'status': 1,
          'sent_at': tLate,
        };

        // Set cursor at rowA
        await syncCursorsStore.setCursor(
          cursorKey,
          DateTime.parse(rowA['sent_at']! as String).microsecondsSinceEpoch,
          syncId: rowA['id']! as String,
        );

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => [rowB, rowC],
        );

        expect(count, equals(2));
        expect(messagesStore.getMessage('AAA-001'), isNotNull);
        expect(messagesStore.getMessage('BBB-002'), isNotNull);

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor!.lastSyncId, equals('BBB-002'));
        expect(
          cursor.lastSyncTimestamp,
          equals(DateTime.parse(tLate).microsecondsSinceEpoch),
        );

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 3: Page boundary containing sub-millisecond timestamps
    // -------------------------------------------------------------------------
    test(
      'Test 3: Page boundary containing sub-millisecond timestamps paginates cleanly',
      () async {
        final t1 = '2026-10-23T10:00:00.123100Z';
        final t2 = '2026-10-23T10:00:00.123456Z';
        final t3 = '2026-10-23T10:00:00.123999Z';

        final allRecords = [
          {
            'id': 'msg-boundary-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Item 1',
            'type': 'text',
            'status': 1,
            'sent_at': t1,
          },
          {
            'id': 'msg-boundary-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Item 2',
            'type': 'text',
            'status': 1,
            'sent_at': t2,
          },
          {
            'id': 'msg-boundary-3',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Item 3',
            'type': 'text',
            'status': 1,
            'sent_at': t3,
          },
        ];

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final requestedBoundaries = <DateTime>[];
        final requestedLastIds = <String?>[];

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            requestedBoundaries.add(after);
            requestedLastIds.add(lastId);

            return allRecords
                .where((r) {
                  final rDt = DateTime.parse(r['sent_at'] as String);
                  final rId = r['id'] as String;
                  if (rDt.isAfter(after)) return true;
                  if (rDt.isAtSameMomentAs(after)) {
                    if (lastId == null || lastId.isEmpty) return true;
                    return rId.compareTo(lastId) > 0;
                  }
                  return false;
                })
                .take(limit)
                .toList();
          },
        );

        expect(count, equals(3));
        expect(messagesStore.getMessage('msg-boundary-1'), isNotNull);
        expect(messagesStore.getMessage('msg-boundary-2'), isNotNull);
        expect(messagesStore.getMessage('msg-boundary-3'), isNotNull);

        expect(requestedBoundaries.length, equals(2));
        expect(requestedBoundaries[1], equals(DateTime.parse(t2)));
        expect(requestedLastIds[1], equals('msg-boundary-2'));

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(
          finalCursor!.lastSyncTimestamp,
          equals(DateTime.parse(t3).microsecondsSinceEpoch),
        );
        expect(finalCursor.lastSyncId, equals('msg-boundary-3'));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 4: Overlapping page with a genuinely later record (Starvation reproduction)
    // -------------------------------------------------------------------------
    test(
      'Test 4: Overlapping page with duplicate rows and a genuinely later row does not starve',
      () async {
        final t1 = '2026-10-23T10:00:00.123100Z';
        final t2 = '2026-10-23T10:00:00.123456Z';
        final t3 = '2026-10-23T10:00:00.123999Z';

        final msg1 = {
          'id': '11111111-1111-1111-1111-111111111111',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Msg 1',
          'type': 'text',
          'status': 1,
          'sent_at': t1,
        };
        final msg2 = {
          'id': '22222222-2222-2222-2222-222222222222',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Msg 2',
          'type': 'text',
          'status': 1,
          'sent_at': t2,
        };
        final msg3 = {
          'id': '00000000-0000-0000-0000-000000000000',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Msg 3',
          'type': 'text',
          'status': 1,
          'sent_at': t3,
        };

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        int callIndex = 0;
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            callIndex++;
            if (callIndex == 1) {
              return [msg1, msg2];
            } else {
              return [msg2, msg3];
            }
          },
        );

        expect(count, equals(3));
        expect(messagesStore.getMessage(msg1['id'] as String), isNotNull);
        expect(messagesStore.getMessage(msg2['id'] as String), isNotNull);
        expect(messagesStore.getMessage(msg3['id'] as String), isNotNull);

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(
          finalCursor!.lastSyncTimestamp,
          equals(DateTime.parse(t3).microsecondsSinceEpoch),
        );
        expect(finalCursor.lastSyncId, equals(msg3['id']));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 5: Cursor persistence and restoration across simulated app restart
    // -------------------------------------------------------------------------
    test(
      'Test 5: Full-precision cursor persists and restores across simulated restart',
      () async {
        final tExact = '2026-10-23T10:00:00.987654Z';
        final exactMicros = DateTime.parse(tExact).microsecondsSinceEpoch;

        await syncCursorsStore.setCursor(
          cursorKey,
          exactMicros,
          syncId: 'uuid-restart-boundary',
          isoString: tExact,
        );

        await cursorBox.close();
        final reopenedBox = await Hive.openBox('sync_cursors_$accountId');
        final newStore = SyncCursorsStore(reopenedBox);

        final restored = newStore.getCursor(cursorKey);
        expect(restored, isNotNull);
        expect(restored!.lastSyncTimestamp, equals(exactMicros));
        expect(restored.lastSyncId, equals('uuid-restart-boundary'));
        expect(restored.version, equals(SyncCursor.currentVersion));

        DateTime? requestedAfter;
        String? requestedId;

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: newStore,
        );

        await service.syncMessages(
          chatId: chatId,
          batchSize: 5,
          customFetcher: (after, lastId, limit) async {
            requestedAfter = after;
            requestedId = lastId;
            return [];
          },
        );

        expect(requestedAfter, equals(DateTime.parse(tExact)));
        expect(requestedId, equals('uuid-restart-boundary'));

        await service.stop();
        if (reopenedBox.isOpen) await reopenedBox.close();
        cursorBox = await Hive.openBox('sync_cursors_$accountId');
      },
    );

    // -------------------------------------------------------------------------
    // Test 6: Local persistence failure does not advance cursor beyond successful rows
    // -------------------------------------------------------------------------
    test(
      'Test 6: Local persistence failure does not advance cursor beyond successfully persisted record',
      () async {
        final t1 = '2026-10-23T10:00:00.100000Z';
        final t2 = '2026-10-23T10:00:00.200000Z';
        final t3 = '2026-10-23T10:00:00.300000Z';

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final batch1 = [
          {
            'id': 'msg-ok-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'OK 1',
            'type': 'text',
            'status': 1,
            'sent_at': t1,
          },
        ];
        await service.syncMessages(
          chatId: chatId,
          batchSize: 5,
          customFetcher: (after, lastId, limit) async => batch1,
        );

        final cursor1 = syncCursorsStore.getCursor(cursorKey);
        expect(cursor1!.lastSyncId, equals('msg-ok-1'));

        final batch2 = [
          {
            'id': 'msg-ok-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'OK 2',
            'type': 'text',
            'status': 1,
            'sent_at': t2,
          },
          {
            'id': 'msg-fail-3',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Fail 3',
            'type': 'text',
            'status': 1,
            'sent_at': t3,
          },
        ];

        await msgBox.close();

        await service.syncMessages(
          chatId: chatId,
          batchSize: 5,
          customFetcher: (after, lastId, limit) async => batch2,
        );

        final cursorAfterFail = syncCursorsStore.getCursor(cursorKey);
        expect(cursorAfterFail!.lastSyncId, equals('msg-ok-1'));

        await service.stop();
        msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      },
    );

    // -------------------------------------------------------------------------
    // Test 7: Later pagination-page failure preserves earlier page committed progress
    // -------------------------------------------------------------------------
    test(
      'Test 7: Failure in later pagination page preserves previously committed cursor progress',
      () async {
        final t0 = DateTime.utc(2026, 10, 24, 12, 0, 0);

        final page1 = [
          {
            'id': 'msg-p1-1',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 1 item 1',
            'type': 'text',
            'status': 1,
            'sent_at': t0.toIso8601String(),
          },
          {
            'id': 'msg-p1-2',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 1 item 2',
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

        int calls = 0;
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            calls++;
            if (calls == 1) return page1;
            throw const SocketException('Connection timed out on Page 2');
          },
        );

        expect(count, equals(2));
        expect(messagesStore.getMessage('msg-p1-1'), isNotNull);
        expect(messagesStore.getMessage('msg-p1-2'), isNotNull);

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor!.lastSyncId, equals('msg-p1-2'));

        final page2 = [
          {
            'id': 'msg-p2-3',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Page 2 item 3',
            'type': 'text',
            'status': 1,
            'sent_at': t0.add(const Duration(minutes: 2)).toIso8601String(),
          },
        ];

        final retryCount = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            expect(lastId, equals('msg-p1-2'));
            return page2;
          },
        );

        expect(retryCount, equals(1));
        expect(messagesStore.getMessage('msg-p2-3'), isNotNull);

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(finalCursor!.lastSyncId, equals('msg-p2-3'));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 8: Duplicate Realtime and catch-up delivery
    // -------------------------------------------------------------------------
    test(
      'Test 8: Duplicate Realtime and catch-up delivery merges idempotently without regression',
      () async {
        final t = '2026-10-23T10:00:00.123456Z';

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final remotePayload = {
          'id': 'msg-dup-1',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Hello world',
          'type': 'text',
          'status': 2,
          'sent_at': t,
        };

        await service.reconcileRemoteMessage(remotePayload);
        final msgAfterRealtime = messagesStore.getMessage('msg-dup-1');
        expect(msgAfterRealtime, isNotNull);
        expect(
          msgAfterRealtime!.deliveryState,
          equals(DeliveryState.delivered),
        );

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => [remotePayload],
        );

        expect(count, equals(1));
        final msgAfterSync = messagesStore.getMessage('msg-dup-1');
        expect(msgAfterSync, isNotNull);
        expect(msgAfterSync!.deliveryState, equals(DeliveryState.delivered));

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor!.lastSyncId, equals('msg-dup-1'));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 9: Legacy cursor compatibility
    // -------------------------------------------------------------------------
    test(
      'Test 9: Legacy epoch-millisecond cursor is correctly migrated to microseconds without magnitude guesswork',
      () async {
        final legacyMs = 1729771200123;
        await cursorBox.put(cursorKey, {
          'cursorKey': cursorKey,
          'lastSyncTimestamp': legacyMs,
          'lastSyncId': 'legacy-msg-uuid',
        });

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor, isNotNull);
        expect(cursor!.version, equals(SyncCursor.currentVersion));
        expect(cursor.lastSyncTimestamp, equals(legacyMs * 1000));
        expect(cursor.lastSyncId, equals('legacy-msg-uuid'));

        final migrated = await syncCursorsStore.migrateCursorIfNeeded(
          cursorKey,
        );
        expect(migrated, isNotNull);
        expect(migrated!.version, equals(SyncCursor.currentVersion));
        expect(migrated.lastSyncTimestamp, equals(legacyMs * 1000));

        final rawPersisted = cursorBox.get(cursorKey) as Map;
        expect(rawPersisted['version'], equals(SyncCursor.currentVersion));
        expect(
          rawPersisted['lastSyncTimestampMicros'],
          equals(legacyMs * 1000),
        );
      },
    );

    test(
      'Test 9b: Legacy cursor persists and restores across simulated restart and repeated migrations',
      () async {
        final legacyMs = 1729771200999;
        const legacyId = 'legacy-msg-uuid-999';
        await cursorBox.put(cursorKey, {
          'cursorKey': cursorKey,
          'lastSyncTimestamp': legacyMs,
          'lastSyncId': legacyId,
        });

        // Migrate
        final migrated1 = await syncCursorsStore.migrateCursorIfNeeded(
          cursorKey,
        );
        expect(migrated1, isNotNull);
        expect(migrated1!.lastSyncTimestamp, equals(legacyMs * 1000));
        expect(migrated1.version, equals(SyncCursor.currentVersion));

        // Simulate app restart: close and reopen Hive box
        await cursorBox.close();
        final reopenedBox = await Hive.openBox('sync_cursors_$accountId');
        final storeAfterRestart = SyncCursorsStore(reopenedBox);

        // Restoration after restart
        final restored = storeAfterRestart.getCursor(cursorKey);
        expect(restored, isNotNull);
        expect(restored!.lastSyncTimestamp, equals(legacyMs * 1000));
        expect(restored.lastSyncId, equals(legacyId));
        expect(restored.version, equals(SyncCursor.currentVersion));

        // Repeated migration is a no-op that safely returns the already-migrated cursor
        final repeatedMigration = await storeAfterRestart.migrateCursorIfNeeded(
          cursorKey,
        );
        expect(repeatedMigration, isNotNull);
        expect(repeatedMigration!.lastSyncTimestamp, equals(legacyMs * 1000));
        expect(repeatedMigration.lastSyncId, equals(legacyId));
        expect(repeatedMigration.version, equals(SyncCursor.currentVersion));

        await reopenedBox.close();
        cursorBox = await Hive.openBox('sync_cursors_$accountId');
        syncCursorsStore = SyncCursorsStore(cursorBox);
      },
    );

    test(
      'Test 9c: Sync cursor stores enforce strict account isolation',
      () async {
        const userBobId = 'user-bob-isolated-test';
        final bobBox = await Hive.openBox('sync_cursors_$userBobId');
        final bobStore = SyncCursorsStore(bobBox);

        try {
          final tAlice = '2026-10-23T10:00:00.123456Z';
          final aliceMicros = DateTime.parse(tAlice).microsecondsSinceEpoch;
          await syncCursorsStore.setCursor(
            cursorKey,
            aliceMicros,
            syncId: 'alice-cursor-id',
          );

          // Bob's box does NOT contain Alice's cursor
          expect(bobStore.getCursor(cursorKey), isNull);
          expect(bobBox.containsKey(cursorKey), isFalse);

          // Set Bob's cursor for a different position
          final tBob = '2026-10-23T11:00:00.654321Z';
          final bobMicros = DateTime.parse(tBob).microsecondsSinceEpoch;
          await bobStore.setCursor(
            cursorKey,
            bobMicros,
            syncId: 'bob-cursor-id',
          );

          // Verify isolation
          final aliceCursor = syncCursorsStore.getCursor(cursorKey);
          final bobCursor = bobStore.getCursor(cursorKey);
          expect(aliceCursor!.lastSyncTimestamp, equals(aliceMicros));
          expect(aliceCursor.lastSyncId, equals('alice-cursor-id'));
          expect(bobCursor!.lastSyncTimestamp, equals(bobMicros));
          expect(bobCursor.lastSyncId, equals('bob-cursor-id'));
        } finally {
          await bobBox.close();
        }
      },
    );

    test(
      'Test 9d: Missing or malformed cursor records are handled gracefully without corruption',
      () async {
        // 1. Missing cursor
        expect(syncCursorsStore.getCursor('non_existent_key'), isNull);
        expect(
          await syncCursorsStore.migrateCursorIfNeeded('non_existent_key'),
          isNull,
        );

        // 2. Corrupted raw type (non-Map)
        await cursorBox.put('corrupt_str_key', 'not_a_map_value');
        expect(syncCursorsStore.getCursor('corrupt_str_key'), isNull);
        expect(
          await syncCursorsStore.migrateCursorIfNeeded('corrupt_str_key'),
          isNull,
        );

        // 3. Corrupted fields inside Map (string instead of numeric timestamp)
        await cursorBox.put('corrupt_map_key', {
          'cursorKey': 'corrupt_map_key',
          'lastSyncTimestamp': 'corrupted_string_not_int',
          'version': 1,
        });
        // Should not throw type cast exception
        final cursor = syncCursorsStore.getCursor('corrupt_map_key');
        expect(cursor, isNotNull);
        expect(cursor!.lastSyncTimestamp, equals(0));

        // 4. Batch migration ignores corrupted entries safely
        final count = await syncCursorsStore.migrateAllLegacyCursors();
        expect(count, greaterThanOrEqualTo(1));
      },
    );

    test(
      'Test 9e: Safe incremental continuation immediately after legacy cursor migration',
      () async {
        // Setup a legacy v1 cursor at 10:00:00.500 (stored as epoch ms)
        final baseDt = DateTime.parse('2026-10-23T10:00:00.500000Z');
        final legacyMs = baseDt.millisecondsSinceEpoch;
        await cursorBox.put(cursorKey, {
          'cursorKey': cursorKey,
          'lastSyncTimestamp': legacyMs,
          'lastSyncId': 'msg-legacy-committed',
          'version': 1,
        });

        // Migrate
        final migrated = await syncCursorsStore.migrateCursorIfNeeded(
          cursorKey,
        );
        expect(migrated, isNotNull);
        expect(migrated!.lastSyncTimestamp, equals(legacyMs * 1000));

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        DateTime? queriedAfter;
        String? queriedLastId;

        // Remote has 1 new record at 10:00:00.500050Z (sub-ms after legacy cursor)
        final tNew = '2026-10-23T10:00:00.500050Z';
        final newRecord = {
          'id': 'msg-after-legacy',
          'chat_id': chatId,
          'sender_id': otherUserId,
          'text': 'Immediately after legacy',
          'type': 'text',
          'status': 1,
          'sent_at': tNew,
        };

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async {
            queriedAfter = after;
            queriedLastId = lastId;
            return [newRecord];
          },
        );

        // Verify resumption query used the migrated microsecond boundary
        expect(
          queriedAfter,
          equals(
            DateTime.fromMicrosecondsSinceEpoch(legacyMs * 1000, isUtc: true),
          ),
        );
        expect(queriedLastId, equals('msg-legacy-committed'));
        expect(count, equals(1));
        expect(messagesStore.getMessage('msg-after-legacy'), isNotNull);

        // Cursor is updated to the new record
        final updatedCursor = syncCursorsStore.getCursor(cursorKey);
        expect(updatedCursor!.lastSyncId, equals('msg-after-legacy'));
        expect(
          updatedCursor.lastSyncTimestamp,
          equals(DateTime.parse(tNew).microsecondsSinceEpoch),
        );

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 10: Strict cursor progress terminates on zero forward progress
    // -------------------------------------------------------------------------
    test(
      'Test 10: Server page producing zero forward progress safely breaks without infinite loop',
      () async {
        final t = '2026-10-23T10:00:00.123456Z';

        await syncCursorsStore.setCursor(
          cursorKey,
          DateTime.parse(t).microsecondsSinceEpoch,
          syncId: 'msg-static-1',
        );

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        int calls = 0;
        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 2,
          customFetcher: (after, lastId, limit) async {
            calls++;
            return [
              {
                'id': 'msg-static-1',
                'chat_id': chatId,
                'sender_id': otherUserId,
                'text': 'Static',
                'type': 'text',
                'status': 1,
                'sent_at': t,
              },
            ];
          },
        );

        expect(calls, equals(1));
        expect(count, equals(0));

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor!.lastSyncId, equals('msg-static-1'));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 11: Exact cursor boundary conditions
    // -------------------------------------------------------------------------
    test(
      'Test 11: Exact compound boundary conditions check before, equal, and after cursor',
      () async {
        final tCursor = '2026-10-23T10:00:00.500000Z';
        final cursorDt = DateTime.parse(tCursor);
        final cursorMicros = cursorDt.microsecondsSinceEpoch;
        const cursorId = 'id-middle';

        await syncCursorsStore.setCursor(
          cursorKey,
          cursorMicros,
          syncId: cursorId,
        );

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        final records = [
          {
            'id': 'id-before',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Before',
            'type': 'text',
            'status': 1,
            'sent_at': cursorDt
                .subtract(const Duration(microseconds: 1))
                .toIso8601String(),
          },
          {
            'id': 'id-alpha',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Same time, smaller ID',
            'type': 'text',
            'status': 1,
            'sent_at': tCursor,
          },
          {
            'id': 'id-middle',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Same time, same ID',
            'type': 'text',
            'status': 1,
            'sent_at': tCursor,
          },
          {
            'id': 'id-omega',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'Same time, greater ID',
            'type': 'text',
            'status': 1,
            'sent_at': tCursor,
          },
          {
            'id': 'id-aaa',
            'chat_id': chatId,
            'sender_id': otherUserId,
            'text': 'After, smaller ID',
            'type': 'text',
            'status': 1,
            'sent_at': cursorDt
                .add(const Duration(microseconds: 1))
                .toIso8601String(),
          },
        ];

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => records,
        );

        expect(count, equals(2));
        expect(messagesStore.getMessage('id-before'), isNull);
        expect(messagesStore.getMessage('id-alpha'), isNull);
        expect(messagesStore.getMessage('id-middle'), isNull);
        expect(messagesStore.getMessage('id-omega'), isNotNull);
        expect(messagesStore.getMessage('id-aaa'), isNotNull);

        final finalCursor = syncCursorsStore.getCursor(cursorKey);
        expect(finalCursor!.lastSyncId, equals('id-aaa'));
        expect(finalCursor.lastSyncTimestamp, equals(cursorMicros + 1));

        await service.stop();
      },
    );

    // -------------------------------------------------------------------------
    // Test 12: Cursor monotonicity ensures committed cursor cannot move backwards
    // -------------------------------------------------------------------------
    test(
      'Test 12: Cursor monotonicity is strictly maintained across retries and duplicate events',
      () async {
        final t1 = '2026-10-23T10:00:00.100000Z';
        final t2 = '2026-10-23T10:00:00.200000Z';
        final micros2 = DateTime.parse(t2).microsecondsSinceEpoch;

        final service = ReconciliationService(
          accountId: accountId,
          messagesStore: messagesStore,
          chatsStore: chatsStore,
          syncCursorsStore: syncCursorsStore,
        );

        await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => [
            {
              'id': 'msg-mono-2',
              'chat_id': chatId,
              'sender_id': otherUserId,
              'text': 'Mono 2',
              'type': 'text',
              'status': 1,
              'sent_at': t2,
            },
          ],
        );

        final cursor = syncCursorsStore.getCursor(cursorKey);
        expect(cursor!.lastSyncTimestamp, equals(micros2));

        final count = await service.syncMessages(
          chatId: chatId,
          batchSize: 10,
          customFetcher: (after, lastId, limit) async => [
            {
              'id': 'msg-mono-1',
              'chat_id': chatId,
              'sender_id': otherUserId,
              'text': 'Mono 1',
              'type': 'text',
              'status': 1,
              'sent_at': t1,
            },
          ],
        );

        expect(count, equals(0));
        final cursorAfter = syncCursorsStore.getCursor(cursorKey);
        expect(cursorAfter!.lastSyncTimestamp, equals(micros2));
        expect(cursorAfter.lastSyncId, equals('msg-mono-2'));

        await service.stop();
      },
    );
  });
}
