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
  bool get hasNetworkInterface => false; // Stay offline so mutations stay queued

  @override
  bool get isBackendReachable => false;

  @override
  BackendReachabilityStatus get backendReachabilityStatus =>
      BackendReachabilityStatus.unreachable;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => const Stream.empty();

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbox Multi-Account Isolation & Lifecycle Tests', () {
    late Directory tempDir;
    late _FakeConnectivityService connectivity;
    final manager = HiveDatabaseManager.instance;

    const userAlice = 'user-alice-iso-test';
    const userBob = 'user-bob-iso-test';
    const chatAlice = 'chat-alice-123';
    const chatBob = 'chat-bob-456';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('outbox_isolation_test_');
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
      'User A outbox mutations are completely isolated from User B',
      () async {
        // 1. User Alice logs in
        final aliceDb = await manager.openAccount(userAlice);
        final aliceDaemon = OutboxDaemon(
          accountId: userAlice,
          outboxStore: aliceDb.outboxStore,
          messagesStore: aliceDb.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async => true,
        );
        await aliceDaemon.start();
        aliceDb.outboxDaemon = aliceDaemon;

        final aliceMsg = ChatMessage(
          id: 'msg-alice-isolated',
          chatId: chatAlice,
          senderId: userAlice,
          text: 'Alice private outbox message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );

        await aliceDb.messagesStore.saveMessage(aliceMsg);
        await aliceDaemon.enqueueMessage(
          message: aliceMsg,
          accountId: userAlice,
        );

        expect(aliceDb.outboxStore.getById('msg-alice-isolated'), isNotNull);

        // 2. Alice logs out
        await manager.closeCurrentAccount();
        expect(aliceDaemon.isRunning, isFalse);

        // 3. Bob logs in
        final bobDb = await manager.openAccount(userBob);
        final bobDaemon = OutboxDaemon(
          accountId: userBob,
          outboxStore: bobDb.outboxStore,
          messagesStore: bobDb.messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async => true,
        );
        await bobDaemon.start();
        bobDb.outboxDaemon = bobDaemon;

        // Bob's outbox must be completely empty (zero leaks from Alice)
        expect(bobDb.outboxStore.getAll(), isEmpty);
        expect(bobDb.outboxStore.getById('msg-alice-isolated'), isNull);
        expect(bobDb.messagesStore.getMessage('msg-alice-isolated'), isNull);

        // Bob enqueues his own mutation
        final bobMsg = ChatMessage(
          id: 'msg-bob-isolated',
          chatId: chatBob,
          senderId: userBob,
          text: 'Bob private outbox message',
          sentAt: DateTime.now(),
          type: MessageType.text,
          deliveryState: DeliveryState.sending,
        );
        await bobDb.messagesStore.saveMessage(bobMsg);
        await bobDaemon.enqueueMessage(message: bobMsg, accountId: userBob);

        expect(bobDb.outboxStore.getById('msg-bob-isolated'), isNotNull);
        expect(bobDb.outboxStore.getAll().length, equals(1));

        // 4. Bob logs out
        await manager.closeCurrentAccount();
        expect(bobDaemon.isRunning, isFalse);

        // 5. Alice logs back in
        final aliceDbReopened = await manager.openAccount(userAlice);
        // Alice's outbox contains her mutation, and NOT Bob's
        expect(
          aliceDbReopened.outboxStore.getById('msg-alice-isolated'),
          isNotNull,
        );
        expect(aliceDbReopened.outboxStore.getById('msg-bob-isolated'), isNull);
        expect(
          aliceDbReopened.messagesStore.getMessage('msg-alice-isolated'),
          isNotNull,
        );
        expect(
          aliceDbReopened.messagesStore.getMessage('msg-bob-isolated'),
          isNull,
        );
      },
    );
  });
}
