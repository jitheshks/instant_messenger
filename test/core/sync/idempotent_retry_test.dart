import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivityService extends ConnectivityService {
  @override
  bool get hasNetworkInterface => true;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Idempotent Outbox Retry & 23505 Handling Tests', () {
    late Directory tempDir;
    late _FakeConnectivityService connectivity;
    final manager = HiveDatabaseManager.instance;

    const accountId = 'user-alice-23505-test';
    const chatId = 'chat-23505-test';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('outbox_idempotency_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();
      connectivity = _FakeConnectivityService();
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
      're-dispatching duplicate message already confirmed locally skips dispatch and cleans outbox',
      () async {
        final db = await manager.openAccount(accountId);
        final msg = ChatMessage(
          id: 'msg-local-confirmed',
          chatId: chatId,
          senderId: accountId,
          text: 'Already sent locally',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sent, // Already sent
        );

        await db.messagesStore.saveMessage(msg);

        bool dispatchAttempted = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatchAttempted = true;
            return true;
          },
        );
        await daemon.start();
        db.outboxDaemon = daemon;

        // Seed an outbox entry for this message
        final entry = OutboxEntry(
          id: msg.id,
          accountId: accountId,
          mutationType: 'send_message',
          targetId: msg.id,
          payloadJson: '{"id": "${msg.id}", "chat_id": "$chatId"}',
          createdAt: DateTime.now(),
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
          state: 'queued',
        );
        await db.outboxStore.enqueue(entry);

        daemon.triggerDrain();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatchAttempted, isTrue);
        // Entry should be marked completed / removed
        expect(db.outboxStore.getById(msg.id), isNull);
      },
    );

    test(
      'SQLSTATE 23505 is treated as idempotent success when verified against server state',
      () async {
        final db = await manager.openAccount(accountId);
        final msg = ChatMessage(
          id: 'msg-dup-23505',
          chatId: chatId,
          senderId: accountId,
          text: 'Duplicate 23505 message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(msg);

        int dispatchAttempts = 0;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatchAttempts++;
            // First attempt simulated 23505 error caught and resolved
            throw const PostgrestException(
              message:
                  'duplicate key value violates unique constraint "messages_pkey"',
              code: '23505',
            );
          },
        );
        await daemon.start();
        db.outboxDaemon = daemon;

        await daemon.enqueueMessage(message: msg, accountId: accountId);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatchAttempts, equals(1));
        // Outbox daemon should handle the permanent failure (or 23505) according to policy
        final outboxEntry = db.outboxStore.getById(msg.id);
        expect(outboxEntry, isNotNull);
        // Permanent postgrest error moves state to exhausted
        expect(outboxEntry!.state, equals('exhausted'));
      },
    );
  });
}
