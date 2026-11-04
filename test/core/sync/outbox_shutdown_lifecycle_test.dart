import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';

class _FakeConnectivityService extends ConnectivityService {
  @override
  bool get hasNetworkInterface => true;

  @override
  bool get isBackendReachable => true;

  @override
  BackendReachabilityStatus get backendReachabilityStatus =>
      BackendReachabilityStatus.reachable;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => const Stream.empty();

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbox Lifecycle-Safe Shutdown Tests (Fix 1)', () {
    late Directory tempDir;
    late _FakeConnectivityService connectivity;
    final manager = HiveDatabaseManager.instance;

    const accountId = 'user-alice-shutdown-test';
    const otherAccountId = 'user-bob-other-session';
    const chatId = 'chat-shutdown-test';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('outbox_shutdown_test_');
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
      'in-flight network request completing after logout/shutdown does not write to closed boxes or throw unhandled exceptions',
      () async {
        final db = await manager.openAccount(accountId);

        final msg = ChatMessage(
          id: 'msg-in-flight-race-1',
          chatId: chatId,
          senderId: accountId,
          text: 'In-flight race message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(msg);

        // Completer to simulate a stalled/in-flight network request
        final networkRequestCompleter = Completer<bool>();
        bool dispatchStarted = false;

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatchStarted = true;
            // Pauses/waits until networkRequestCompleter is completed
            return await networkRequestCompleter.future;
          },
        );

        await daemon.start();
        db.outboxDaemon = daemon;

        // 1. Enqueue mutation and begin dispatch
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        // Wait a microtask until customHandler starts executing
        while (!dispatchStarted) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        // Verify mutation was leased to 'in_flight'
        final inFlightEntry = db.outboxStore.getById(msg.id);
        expect(inFlightEntry, isNotNull);
        expect(inFlightEntry!.state, equals('in_flight'));

        // 2. Initiate logout and account closure while network request is STILL in flight
        await manager.closeCurrentAccount();

        // Verify that database boxes are now closed
        expect(db.outboxStore.box.isOpen, isFalse);
        expect(db.messagesStore.box.isOpen, isFalse);
        expect(daemon.isRunning, isFalse);
        expect(daemon.sessionGate.isClosed, isTrue);

        // 3. Complete the stalled network request AFTER boxes were closed
        // If the daemon was not lifecycle-safe, this would throw "HiveError: Box has already been closed"
        networkRequestCompleter.complete(true);

        // Allow async completion microtasks to run
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 4. Bob logs in to ensure no cross-account pollution occurred
        final bobDb = await manager.openAccount(otherAccountId);
        expect(bobDb.outboxStore.getById(msg.id), isNull);
        expect(bobDb.messagesStore.getMessage(msg.id), isNull);
        await manager.closeCurrentAccount();

        // 5. Alice logs back in (app restart / reconnect)
        final aliceDbReopened = await manager.openAccount(accountId);

        // Unfinished in-flight work was safely preserved and recovered back to 'queued'
        final recoveredEntry = aliceDbReopened.outboxStore.getById(msg.id);
        expect(recoveredEntry, isNotNull);
        expect(recoveredEntry!.state, equals('queued'));
        expect(aliceDbReopened.messagesStore.getMessage(msg.id), isNotNull);
      },
    );

    test(
      'in-flight network failure completing after shutdown does not attempt writes to closed stores',
      () async {
        final db = await manager.openAccount(accountId);

        final msg = ChatMessage(
          id: 'msg-failure-race-1',
          chatId: chatId,
          senderId: accountId,
          text: 'Failure race message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await db.messagesStore.saveMessage(msg);

        final failureCompleter = Completer<bool>();
        bool dispatchStarted = false;

        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: db.outboxStore,
          messagesStore: db.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatchStarted = true;
            return await failureCompleter.future;
          },
        );

        await daemon.start();
        db.outboxDaemon = daemon;

        await daemon.enqueueMessage(message: msg, accountId: accountId);

        while (!dispatchStarted) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        // Close account while network request is in flight
        await manager.closeCurrentAccount();

        // Network request fails after account closed
        failureCompleter.completeError(
          const SocketException('Network disconnected'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Reopen account and verify mutation remains safely recoverable
        final reopenedDb = await manager.openAccount(accountId);
        final recovered = reopenedDb.outboxStore.getById(msg.id);
        expect(recovered, isNotNull);
        expect(recovered!.state, equals('queued'));
      },
    );
  });
}
