import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/outbox_bridge.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/outbox_meta.dart';

void main() {
  group('OutboxBridge Unit Tests', () {
    late Directory tempDir;
    late Box metaBox;
    late Box outboxBox;
    late OutboxStore outboxStore;

    const accountId = 'user-alice-123';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('outbox_bridge_test_');
      Hive.init(tempDir.path);

      metaBox = await Hive.openBox(OutboxBridge.legacyMetaBoxName);
      outboxBox = await Hive.openBox('outbox_mutations_$accountId');
      outboxStore = OutboxStore(outboxBox);
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
      'bridges legacy OutboxMeta records into OutboxStore accurately',
      () async {
        final now = DateTime.now();
        final meta = OutboxMeta(
          messageId: 'msg-media-1',
          chatId: 'chat-alice-bob',
          filePath: '/data/user/0/cache/image_123.jpg',
          mediaKind: MediaKind.image,
          retryCount: 1,
          nextAttemptAt: now.add(const Duration(seconds: 30)),
        );

        await metaBox.put('msg-media-1', meta.toMap());

        final count = await OutboxBridge.bridgeLegacyMeta(
          accountId: accountId,
          metaBox: metaBox,
          outboxStore: outboxStore,
        );

        expect(count, equals(1));

        final entry = outboxStore.getById('msg-media-1');
        expect(entry, isNotNull);
        expect(entry!.id, equals('msg-media-1'));
        expect(entry.accountId, equals(accountId));
        expect(entry.mutationType, equals('attach_media'));
        expect(entry.state, equals('queued'));
        expect(entry.retryCount, equals(1));
        expect(
          entry.payloadJson.contains('/data/user/0/cache/image_123.jpg'),
          isTrue,
        );
      },
    );

    test(
      'is strictly idempotent: repeated bridging does not overwrite or duplicate',
      () async {
        final meta = OutboxMeta(
          messageId: 'msg-media-2',
          chatId: 'chat-alice-bob',
          filePath: '/data/user/0/cache/voice_456.m4a',
          mediaKind: MediaKind.audio,
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
        );

        await metaBox.put('msg-media-2', meta.toMap());

        // Run 1
        final count1 = await OutboxBridge.bridgeLegacyMeta(
          accountId: accountId,
          metaBox: metaBox,
          outboxStore: outboxStore,
        );
        expect(count1, equals(1));

        // Mutate state in store to in_flight
        await outboxStore.updateState('msg-media-2', 'in_flight');

        // Run 2
        final count2 = await OutboxBridge.bridgeLegacyMeta(
          accountId: accountId,
          metaBox: metaBox,
          outboxStore: outboxStore,
        );
        expect(count2, equals(0)); // Skipped because already present

        // Verify state was preserved and not regressed
        expect(outboxStore.getById('msg-media-2')?.state, equals('in_flight'));
      },
    );

    test(
      'preserves legacy outbox_meta records intact for Workmanager background worker',
      () async {
        final meta = OutboxMeta(
          messageId: 'msg-media-3',
          chatId: 'chat-alice-bob',
          filePath: '/data/user/0/cache/video_789.mp4',
          mediaKind: MediaKind.video,
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
        );

        await metaBox.put('msg-media-3', meta.toMap());

        await OutboxBridge.bridgeLegacyMeta(
          accountId: accountId,
          metaBox: metaBox,
          outboxStore: outboxStore,
        );

        // Verify metaBox is unchanged
        expect(metaBox.containsKey('msg-media-3'), isTrue);
        final raw = metaBox.get('msg-media-3');
        expect(raw, isNotNull);
        final readBack = OutboxMeta.fromMap(raw as Map);
        expect(readBack.messageId, equals('msg-media-3'));
      },
    );

    test(
      'recovers in-flight mutations left abandoned after an app crash',
      () async {
        final now = DateTime.now();

        // Mutation 1: in_flight with 1 retry -> should be recovered to queued
        final entry1 = OutboxEntry(
          id: 'mut-1',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-1',
          payloadJson: '{"text": "Hello"}',
          createdAt: now.subtract(const Duration(minutes: 5)),
          retryCount: 1,
          nextAttemptAt: now,
          state: 'in_flight',
        );

        // Mutation 2: queued -> should stay queued
        final entry2 = OutboxEntry(
          id: 'mut-2',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-2',
          payloadJson: '{"text": "World"}',
          createdAt: now.subtract(const Duration(minutes: 2)),
          retryCount: 0,
          nextAttemptAt: now,
          state: 'queued',
        );

        // Mutation 3: in_flight with 5 retries -> under Stage 2B fault tolerance,
        // all in-flight mutations are recovered back to queued on crash recovery
        final entry3 = OutboxEntry(
          id: 'mut-3',
          accountId: accountId,
          mutationType: 'attach_media',
          targetId: 'msg-3',
          payloadJson: '{"url": "broken"}',
          createdAt: now.subtract(const Duration(minutes: 10)),
          retryCount: 5,
          nextAttemptAt: now,
          state: 'in_flight',
        );

        await outboxStore.enqueue(entry1);
        await outboxStore.enqueue(entry2);
        await outboxStore.enqueue(entry3);

        final recovered = await OutboxBridge.recoverInFlight(
          outboxStore,
          maxRetries: 5,
        );
        expect(
          recovered,
          equals(2),
        ); // Both in_flight entries (mut-1 and mut-3) recovered back to queued

        expect(outboxStore.getById('mut-1')?.state, equals('queued'));
        expect(outboxStore.getById('mut-2')?.state, equals('queued'));
        expect(outboxStore.getById('mut-3')?.state, equals('queued'));
      },
    );
  });
}
