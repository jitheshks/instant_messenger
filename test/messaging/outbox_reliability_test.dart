import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/network/retry_policy.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _online;
  BackendReachabilityStatus _reachability;
  final _statusController =
      StreamController<NetworkInterfaceStatus>.broadcast();
  final _reachabilityController =
      StreamController<BackendReachabilityStatus>.broadcast();

  _FakeConnectivityService({
    bool online = true,
    BackendReachabilityStatus reachability =
        BackendReachabilityStatus.reachable,
  })  : _online = online,
        _reachability = reachability;

  @override
  bool get hasNetworkInterface => _online;

  @override
  bool get isBackendReachable =>
      _reachability == BackendReachabilityStatus.reachable;

  @override
  BackendReachabilityStatus get backendReachabilityStatus => _reachability;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged =>
      _statusController.stream;

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      _reachabilityController.stream;

  void setNetworkInterface(bool online) {
    _online = online;
    _statusController.add(
      NetworkInterfaceStatus([
        online ? NetworkInterfaceType.wifi : NetworkInterfaceType.none,
      ]),
    );
  }

  void setBackendReachability(BackendReachabilityStatus status) {
    _reachability = status;
    _reachabilityController.add(status);
  }

  @override
  void dispose() {
    _statusController.close();
    _reachabilityController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage 2B: Outbox Reliability & Fault-Tolerance Tests', () {
    late Directory tempDir;
    late Box<ChatMessage> msgBox;
    late Box outboxBox;
    late MessagesStore messagesStore;
    late OutboxStore outboxStore;
    late _FakeConnectivityService connectivity;
    late List<OutboxDaemon> activeDaemons;

    const accountId = 'user-alice-stage2b';
    const chatId = 'chat-stage2b';

    setUp(() async {
      activeDaemons = [];
      tempDir = Directory.systemTemp.createTempSync('stage2b_outbox_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$accountId');
      outboxBox = await Hive.openBox('outbox_mutations_$accountId');
      messagesStore = MessagesStore(msgBox);
      outboxStore = OutboxStore(outboxBox);
      connectivity = _FakeConnectivityService(
        online: true,
        reachability: BackendReachabilityStatus.reachable,
      );
    });

    tearDown(() async {
      for (final daemon in activeDaemons) {
        daemon.stop();
      }
      activeDaemons.clear();
      connectivity.dispose();
      await Hive.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      '1. Transient network errors NEVER transition to exhausted even after 5+ attempts',
      () async {
        final msg = ChatMessage(
          id: 'msg-transient-loop',
          chatId: chatId,
          senderId: accountId,
          text: 'Persist through outages',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        var dispatchAttempts = 0;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          retryPolicy: RetryPolicy(
            initialDelay: const Duration(milliseconds: 1),
            maxDelay: const Duration(seconds: 60),
            backoffFactor: 1.0, // Constant 1ms backoff for fast testing
          ),
          customHandler: (entry) async {
            dispatchAttempts++;
            throw const SocketException('Network is unreachable (errno 101)');
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        // Let it retry at least 7 times
        for (var i = 0; i < 40; i++) {
          final entry = outboxStore.getById(msg.id);
          if (entry != null && entry.retryCount >= 7) break;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        // Stop the daemon to freeze state for assertion
        await daemon.stop();

        final entry = outboxStore.getById(msg.id);
        expect(entry, isNotNull);
        expect(dispatchAttempts, greaterThanOrEqualTo(5));
        expect(entry!.retryCount, greaterThanOrEqualTo(5));
        // Must NEVER be marked exhausted solely due to retry count
        expect(entry.state, equals('queued'));

        // Local message must remain in sending state without permanent failure
        final localMsg = messagesStore.getMessage(msg.id);
        expect(localMsg, isNotNull);
        expect(localMsg!.deliveryState, equals(DeliveryState.sending));
        expect(localMsg.failure, isNull);

        daemon.dispose();
      },
    );

    test(
      '2. Permanent errors fail fast to exhausted without repetitive retries',
      () async {
        final msg = ChatMessage(
          id: 'msg-permanent-rls',
          chatId: chatId,
          senderId: accountId,
          text: 'Unauthorized send',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        var callCount = 0;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            callCount++;
            throw const PostgrestException(
              message: 'new row violates row-level security policy',
              code: '42501',
            );
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        // Wait for dispatch cycle
        for (var i = 0; i < 20; i++) {
          final entry = outboxStore.getById(msg.id);
          if (entry?.state == 'exhausted') break;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        // Fails fast on attempt 1
        expect(callCount, equals(1));
        final entry = outboxStore.getById(msg.id);
        expect(entry, isNotNull);
        expect(entry!.state, equals('exhausted'));
        expect(entry.retryCount, equals(1));

        final localMsg = messagesStore.getMessage(msg.id);
        expect(localMsg, isNotNull);
        expect(localMsg!.hasFailed, isTrue);
        expect(localMsg.failure, equals(MessageFailureReason.serverFailed));

        daemon.dispose();
      },
    );

    test(
      '3. Queue dispatch is paused when backend is unreachable, preserving pending messages',
      () async {
        // Physical Wi-Fi interface is on, but backend reachability is unreachable
        connectivity.setNetworkInterface(true);
        connectivity.setBackendReachability(BackendReachabilityStatus.unreachable);

        final msg = ChatMessage(
          id: 'msg-paused-when-unreachable',
          chatId: chatId,
          senderId: accountId,
          text: 'Should not attempt network write while unreachable',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        var dispatchAttempted = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            dispatchAttempted = true;
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Dispatch was paused
        expect(dispatchAttempted, isFalse);
        final entry = outboxStore.getById(msg.id);
        expect(entry, isNotNull);
        expect(entry!.state, equals('queued'));
        expect(entry.retryCount, equals(0));

        daemon.dispose();
      },
    );

    test(
      '4. Backend reachability restoration automatically wakes daemon and delivers queued messages immediately',
      () async {
        // Start with backend unreachable
        connectivity.setNetworkInterface(true);
        connectivity.setBackendReachability(BackendReachabilityStatus.unreachable);

        final msg = ChatMessage(
          id: 'msg-wake-on-reachability',
          chatId: chatId,
          senderId: accountId,
          text: 'Deliver upon reachability restoration',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        var delivered = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            delivered = true;
            return true;
          },
        );
        activeDaemons.add(daemon);

        await daemon.start();
        await daemon.enqueueMessage(message: msg, accountId: accountId);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(delivered, isFalse);

        // Backend reachability recovers!
        connectivity.setBackendReachability(BackendReachabilityStatus.reachable);

        // Allow drain cycle to complete
        for (var i = 0; i < 20; i++) {
          if (delivered) break;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        expect(delivered, isTrue);
        expect(outboxStore.getById(msg.id), isNull);
        expect(
          messagesStore.getMessage(msg.id)?.deliveryState,
          equals(DeliveryState.sent),
        );

        daemon.dispose();
      },
    );

    test(
      '5. recoverInFlight() safely requeues in-flight mutations regardless of prior retry count',
      () async {
        // Seed an in-flight mutation that had 10 previous retries
        final inFlightEntry = OutboxEntry(
          id: 'msg-crashed-in-flight',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-crashed-in-flight',
          payloadJson: '{"id": "msg-crashed-in-flight"}',
          createdAt: DateTime.now(),
          retryCount: 10,
          nextAttemptAt: DateTime.now(),
          state: 'in_flight',
        );
        await outboxStore.enqueue(inFlightEntry);

        final recoveredCount = await outboxStore.recoverInFlight();
        expect(recoveredCount, equals(1));

        final recovered = outboxStore.getById('msg-crashed-in-flight');
        expect(recovered, isNotNull);
        expect(recovered!.state, equals('queued'));
        expect(recovered.retryCount, equals(10));
      },
    );

    test(
      '6. MessagesRepository.retryMessage() triggers immediate outbox recovery and dispatch',
      () async {
        final msg = ChatMessage(
          id: 'msg-manual-retry',
          chatId: chatId,
          senderId: accountId,
          text: 'Manual retry message',
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          failure: MessageFailureReason.serverFailed,
          type: MessageType.text,
        );

        await messagesStore.saveMessage(msg);

        // Seed exhausted mutation
        final exhaustedEntry = OutboxEntry(
          id: 'msg-manual-retry',
          accountId: accountId,
          mutationType: 'send_message',
          targetId: 'msg-manual-retry',
          payloadJson: '{"text": "Manual retry message"}',
          createdAt: DateTime.now(),
          retryCount: 5,
          nextAttemptAt: DateTime.now(),
          state: 'exhausted',
        );
        await outboxStore.enqueue(exhaustedEntry);

        var retryDispatched = false;
        final daemon = OutboxDaemon(
          accountId: accountId,
          outboxStore: outboxStore,
          messagesStore: messagesStore,
          connectivityService: connectivity,
          customHandler: (entry) async {
            retryDispatched = true;
            return true;
          },
        );
        activeDaemons.add(daemon);
        await daemon.start();

        final repo = MessagesRepository(
          messagesStore: messagesStore,
          outboxDaemon: daemon,
        );

        // Trigger manual retry via repository
        await repo.retryMessage(msg.id);

        for (var i = 0; i < 20; i++) {
          final m = messagesStore.getMessage(msg.id);
          if (m?.deliveryState == DeliveryState.sent) break;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        expect(retryDispatched, isTrue);
        expect(outboxStore.getById(msg.id), isNull);
        expect(
          messagesStore.getMessage(msg.id)?.deliveryState,
          equals(DeliveryState.sent),
        );
        expect(messagesStore.getMessage(msg.id)?.failure, isNull);

        daemon.dispose();
      },
    );
  });
}
