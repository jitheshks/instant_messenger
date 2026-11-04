import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.4 — Reconciliation & Account Lifecycle Tests', () {
    late Directory tempDir;

    const userAlice = 'user-alice-lifecycle-test';
    const userBob = 'user-bob-lifecycle-test';
    const chatId = 'chat-lifecycle-909';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('recon_lifecycle_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
    });

    tearDown(() async {
      await HiveDatabaseManager.instance.closeCurrentAccount();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'account switching cancels old reconciliation and starts isolated service',
      () async {
        // 1. Open Account Alice
        final dbAlice = await HiveDatabaseManager.instance.openAccount(
          userAlice,
        );
        expect(dbAlice.reconciliationService, isNotNull);
        expect(dbAlice.reconciliationService!.isClosed, isFalse);
        final reconAlice = dbAlice.reconciliationService!;

        // Reconcile message in Alice's store
        await reconAlice.reconcileRemoteMessage({
          'id': 'msg-alice-1',
          'chat_id': chatId,
          'sender_id': userAlice,
          'text': 'Alice private note',
          'type': 'text',
          'status': 1,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        });
        expect(dbAlice.messagesStore.getMessage('msg-alice-1'), isNotNull);

        // 2. Switch to Account Bob
        final dbBob = await HiveDatabaseManager.instance.openAccount(userBob);
        expect(dbBob.accountId, equals(userBob));
        expect(dbBob.reconciliationService, isNotNull);
        expect(dbBob.reconciliationService!.isClosed, isFalse);

        // Alice's reconciliation service must now be closed
        expect(reconAlice.isClosed, isTrue);

        // Bob's message store does NOT contain Alice's message (strict multi-account isolation)
        expect(dbBob.messagesStore.getMessage('msg-alice-1'), isNull);

        // Reconcile message in Bob's store
        await dbBob.reconciliationService!.reconcileRemoteMessage({
          'id': 'msg-bob-1',
          'chat_id': chatId,
          'sender_id': userBob,
          'text': 'Bob private note',
          'type': 'text',
          'status': 1,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        });
        expect(dbBob.messagesStore.getMessage('msg-bob-1'), isNotNull);
      },
    );

    test(
      'logout during active synchronization stops cleanly without throwing',
      () async {
        final db = await HiveDatabaseManager.instance.openAccount(userAlice);
        final recon = db.reconciliationService!;

        final syncStarted = Completer<void>();
        final syncFinish = Completer<List<Map<String, dynamic>>>();

        // Start an incremental sync operation with a delayed fetcher
        final syncFuture = recon.syncMessages(
          chatId: chatId,
          customFetcher: (after, lastId, limit) async {
            syncStarted.complete();
            return syncFinish.future;
          },
        );

        // Wait until sync begins
        await syncStarted.future;

        // Close account (logout) while sync is in-flight
        await HiveDatabaseManager.instance.closeCurrentAccount();
        expect(recon.isClosed, isTrue);

        // Complete the delayed network response after logout
        syncFinish.complete([
          {
            'id': 'msg-late-after-logout',
            'chat_id': chatId,
            'sender_id': 'peer-id',
            'text': 'Late incoming message',
            'type': 'text',
            'status': 1,
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]);

        // syncFuture resolves cleanly to 0 without throwing closed-box exceptions
        final count = await syncFuture;
        expect(count, equals(0));
      },
    );

    test(
      'reconciliation operates compatibly alongside durable outbox',
      () async {
        final db = await HiveDatabaseManager.instance.openAccount(userAlice);

        // Enqueue message into durable outbox
        final msg = ChatMessage(
          id: 'msg-outbox-compat-1',
          chatId: chatId,
          senderId: userAlice,
          text: 'Outbox compatibility check',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await db.messagesStore.saveMessage(msg);
        await db.outboxStore.enqueue(
          OutboxEntry(
            id: msg.id,
            accountId: userAlice,
            mutationType: 'send_message',
            targetId: msg.id,
            payloadJson: '{}',
            createdAt: DateTime.now(),
            nextAttemptAt: DateTime.now(),
          ),
        );

        expect(db.messagesStore.getMessage(msg.id), isNotNull);
        expect(db.outboxStore.getById(msg.id), isNotNull);

        // Remote event arrives acknowledging the message (status 1)
        await db.reconciliationService!.reconcileRemoteMessage({
          'id': msg.id,
          'chat_id': chatId,
          'sender_id': userAlice,
          'text': 'Outbox compatibility check',
          'type': 'text',
          'status': 1, // sent
          'sent_at': msg.sentAt.toIso8601String(),
        });

        await Future<void>.delayed(const Duration(milliseconds: 20));

        // 1. Message delivery state advanced to sent
        final updated = db.messagesStore.getMessage(msg.id);
        expect(updated!.deliveryState, equals(DeliveryState.sent));

        // 2. Outbox daemon notified: outbox entry safely removed
        expect(db.outboxStore.getById(msg.id), isNull);
      },
    );
  });
}
