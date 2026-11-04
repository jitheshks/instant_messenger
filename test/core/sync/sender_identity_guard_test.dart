import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

class _FakeConnectivityService extends ConnectivityService {
  @override
  bool get hasNetworkInterface => true;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sender Identity & Account Isolation Guard Tests (Fix 3)', () {
    late Directory tempDir;
    late _FakeConnectivityService connectivity;
    final manager = HiveDatabaseManager.instance;

    const aliceAccountId = 'user-alice-guard-test';
    const bobAccountId = 'user-bob-guard-test';
    const chatId = 'chat-guard-test';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('sender_guard_test_');
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

    test('matching account and sender IDs dispatches successfully', () async {
      final db = await manager.openAccount(aliceAccountId);
      final msg = ChatMessage(
        id: 'msg-valid-sender-1',
        chatId: chatId,
        senderId: aliceAccountId, // Matches daemon account
        text: 'Valid author',
        sentAt: DateTime.now(),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
      );

      await db.messagesStore.saveMessage(msg);

      bool dispatched = false;
      final daemon = OutboxDaemon(
        accountId: aliceAccountId,
        outboxStore: db.outboxStore,
        messagesStore: db.messagesStore,
        connectivityService: connectivity,
        customHandler: (entry) async {
          dispatched = true;
          return true;
        },
      );

      await daemon.start();
      db.outboxDaemon = daemon;

      await daemon.enqueueMessage(message: msg, accountId: aliceAccountId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dispatched, isTrue);
      expect(db.outboxStore.getById(msg.id), isNull);
      expect(
        db.messagesStore.getMessage(msg.id)?.deliveryState,
        equals(DeliveryState.sent),
      );
    });

    test(
      'mutation with alien entry.accountId is rejected permanently as exhausted and never dispatched',
      () async {
        final db = await manager.openAccount(aliceAccountId);
        final msg = ChatMessage(
          id: 'msg-alien-account-1',
          chatId: chatId,
          senderId: aliceAccountId,
          text: 'Alien account entry',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(msg);

        // Pre-seed an outbox entry with Bob's accountId in Alice's box (e.g. corrupted/foreign entry)
        final alienEntry = OutboxEntry(
          id: msg.id,
          accountId: bobAccountId, // Mismatch!
          mutationType: 'send_message',
          targetId: msg.id,
          payloadJson: jsonEncode(msg.toMap()),
          createdAt: DateTime.now(),
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
          state: 'queued',
        );
        await db.outboxStore.enqueue(alienEntry);

        final daemon = OutboxDaemon(
          accountId: aliceAccountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
        );

        await daemon.start();
        db.outboxDaemon = daemon;

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Must be exhausted (permanent failure) to prevent dispatch
        final result = db.outboxStore.getById(msg.id);
        expect(result, isNotNull);
        expect(result!.state, equals('exhausted'));
        expect(db.messagesStore.getMessage(msg.id)?.hasFailed, isTrue);
      },
    );

    test(
      'mutation with message senderId differing from daemon accountId is rejected permanently',
      () async {
        final db = await manager.openAccount(aliceAccountId);
        final alienMsg = ChatMessage(
          id: 'msg-alien-sender-1',
          chatId: chatId,
          senderId:
              bobAccountId, // Message says Bob is author, but daemon is Alice
          text: 'Spoofed author',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(alienMsg);

        final entry = OutboxEntry(
          id: alienMsg.id,
          accountId: aliceAccountId,
          mutationType: 'send_message',
          targetId: alienMsg.id,
          payloadJson: jsonEncode(alienMsg.toMap()),
          createdAt: DateTime.now(),
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
          state: 'queued',
        );
        await db.outboxStore.enqueue(entry);

        final daemon = OutboxDaemon(
          accountId: aliceAccountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
        );

        await daemon.start();
        db.outboxDaemon = daemon;

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Must be permanently exhausted
        final result = db.outboxStore.getById(alienMsg.id);
        expect(result, isNotNull);
        expect(result!.state, equals('exhausted'));
      },
    );

    test(
      'safe recovery of rejected mutation without accidental dispatch under wrong identity',
      () async {
        final db = await manager.openAccount(aliceAccountId);
        final alienMsg = ChatMessage(
          id: 'msg-recover-identity-1',
          chatId: chatId,
          senderId: bobAccountId,
          text: 'Needs identity fix',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(alienMsg);

        final entry = OutboxEntry(
          id: alienMsg.id,
          accountId: aliceAccountId,
          mutationType: 'send_message',
          targetId: alienMsg.id,
          payloadJson: jsonEncode(alienMsg.toMap()),
          createdAt: DateTime.now(),
          retryCount: 0,
          nextAttemptAt: DateTime.now(),
          state: 'queued',
        );
        await db.outboxStore.enqueue(entry);

        final daemon = OutboxDaemon(
          accountId: aliceAccountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
        );

        await daemon.start();
        db.outboxDaemon = daemon;

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 1. Rejected as exhausted
        expect(db.outboxStore.getById(alienMsg.id)?.state, equals('exhausted'));

        // 2. Correct the senderId in payload to Alice
        final correctedMsg = alienMsg.copyWith(senderId: aliceAccountId);
        await db.messagesStore.saveMessage(correctedMsg);
        await db.outboxStore.enqueue(
          entry.copyWith(
            payloadJson: jsonEncode(correctedMsg.toMap()),
            state: 'exhausted',
          ),
        );

        // 3. User manually retries exhausted mutation
        bool dispatchedCorrectly = false;
        final retryDaemon = OutboxDaemon(
          accountId: aliceAccountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            final payload = jsonDecode(entry.payloadJson);
            expect(payload['senderId'], equals(aliceAccountId));
            dispatchedCorrectly = true;
            return true;
          },
        );
        await retryDaemon.start();
        db.outboxDaemon = retryDaemon;

        await retryDaemon.retryExhausted(alienMsg.id);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(dispatchedCorrectly, isTrue);
        expect(db.outboxStore.getById(alienMsg.id), isNull);
      },
    );
  });
}
