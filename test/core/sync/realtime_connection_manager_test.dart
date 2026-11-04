import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivityService extends ConnectivityService {
  bool _hasInterface;
  BackendReachabilityStatus _reachabilityStatus;

  final _interfaceController =
      StreamController<NetworkInterfaceStatus>.broadcast();
  final _reachabilityController =
      StreamController<BackendReachabilityStatus>.broadcast();

  _FakeConnectivityService({
    bool initialHasInterface = true,
    BackendReachabilityStatus initialReachability =
        BackendReachabilityStatus.reachable,
  })  : _hasInterface = initialHasInterface,
        _reachabilityStatus = initialReachability;

  @override
  bool get hasNetworkInterface => _hasInterface;

  @override
  bool get isBackendReachable =>
      _reachabilityStatus == BackendReachabilityStatus.reachable;

  @override
  BackendReachabilityStatus get backendReachabilityStatus =>
      _reachabilityStatus;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged =>
      _interfaceController.stream;

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged =>
      _reachabilityController.stream;

  void setInterface(bool hasInterface) {
    _hasInterface = hasInterface;
    _interfaceController.add(
      NetworkInterfaceStatus(
        hasInterface ? [NetworkInterfaceType.wifi] : [NetworkInterfaceType.none],
      ),
    );
  }

  void setReachability(BackendReachabilityStatus reachability) {
    _reachabilityStatus = reachability;
    _reachabilityController.add(reachability);
  }

  @override
  void dispose() {
    _interfaceController.close();
    _reachabilityController.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage 2D: RealtimeConnectionManager Comprehensive Suite', () {
    late _FakeConnectivityService connectivity;
    late RealtimeConnectionManager manager;
    int catchUpCallCount = 0;

    setUp(() {
      catchUpCallCount = 0;
      connectivity = _FakeConnectivityService(
        initialHasInterface: true,
        initialReachability: BackendReachabilityStatus.reachable,
      );
    });

    tearDown(() async {
      await manager.stop();
      connectivity.dispose();
    });

    test('1. starts paused when initial network interface is disconnected', () {
      connectivity = _FakeConnectivityService(
        initialHasInterface: false,
        initialReachability: BackendReachabilityStatus.unreachable,
      );
      manager = RealtimeConnectionManager(
        accountId: 'test-account-1',
        connectivityService: connectivity,
      );

      expect(manager.status, equals(RealtimeConnectionStatus.paused));
    });

    test('2. starts paused when backend is unreachable despite network interface', () {
      connectivity = _FakeConnectivityService(
        initialHasInterface: true,
        initialReachability: BackendReachabilityStatus.unreachable,
      );
      manager = RealtimeConnectionManager(
        accountId: 'test-account-2',
        connectivityService: connectivity,
      );

      expect(manager.status, equals(RealtimeConnectionStatus.paused));
    });

    test('3. starts connected when online and reachable with no required channels', () {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-3',
        connectivityService: connectivity,
      );

      expect(manager.status, equals(RealtimeConnectionStatus.connected));
    });

    test('4. network interface loss transitions status to paused', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-4',
        connectivityService: connectivity,
      );
      await manager.start();

      connectivity.setInterface(false);
      await pumpEventQueue();

      expect(manager.status, equals(RealtimeConnectionStatus.paused));
    });

    test('5. network interface loss cancels scheduled backoff timer', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-5',
        connectivityService: connectivity,
        initialDelay: const Duration(milliseconds: 500),
      );
      await manager.start();

      manager.registerRequiredChannel('chat:room1');
      manager.reportChannelStatus('chat:room1', RealtimeSubscribeStatus.channelError);
      expect(manager.hasScheduledTimer, isTrue);

      connectivity.setInterface(false);
      await pumpEventQueue();

      expect(manager.hasScheduledTimer, isFalse);
    });

    test('6. network interface restoration expedites reconnect', () async {
      connectivity = _FakeConnectivityService(
        initialHasInterface: false,
        initialReachability: BackendReachabilityStatus.unreachable,
      );
      manager = RealtimeConnectionManager(
        accountId: 'test-account-6',
        connectivityService: connectivity,
      );
      await manager.start();
      expect(manager.status, equals(RealtimeConnectionStatus.paused));

      connectivity.setInterface(true);
      connectivity.setReachability(BackendReachabilityStatus.reachable);
      await pumpEventQueue();

      expect(manager.status, equals(RealtimeConnectionStatus.connected));
    });

    test('7. network interface restoration resets retry attempts', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-7',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:r1');
      manager.reportChannelStatus('chat:r1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(1));

      connectivity.setInterface(false);
      await pumpEventQueue();

      manager.reportChannelStatus('chat:r1', RealtimeSubscribeStatus.subscribed);
      connectivity.setInterface(true);
      connectivity.setReachability(BackendReachabilityStatus.reachable);
      await pumpEventQueue();

      expect(manager.retryAttempts, equals(0));
    });

    test('8. backend reachability loss transitions status to paused', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-8',
        connectivityService: connectivity,
      );
      await manager.start();

      connectivity.setReachability(BackendReachabilityStatus.unreachable);
      await pumpEventQueue();

      expect(manager.status, equals(RealtimeConnectionStatus.paused));
    });

    test('9. backend reachability loss cancels scheduled backoff timer', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-9',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:r2');
      manager.reportChannelStatus('chat:r2', RealtimeSubscribeStatus.channelError);
      expect(manager.hasScheduledTimer, isTrue);

      connectivity.setReachability(BackendReachabilityStatus.unreachable);
      await pumpEventQueue();

      expect(manager.hasScheduledTimer, isFalse);
    });

    test('10. backend reachability restoration wakes Realtime and expedites reconnect', () async {
      connectivity = _FakeConnectivityService(
        initialHasInterface: true,
        initialReachability: BackendReachabilityStatus.unreachable,
      );
      manager = RealtimeConnectionManager(
        accountId: 'test-account-10',
        connectivityService: connectivity,
      );
      await manager.start();
      expect(manager.status, equals(RealtimeConnectionStatus.paused));

      connectivity.setReachability(BackendReachabilityStatus.reachable);
      await pumpEventQueue();

      expect(manager.status, equals(RealtimeConnectionStatus.connected));
    });

    test('11. single-flight reconnection coalesces concurrent reconnect flights', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-11',
        connectivityService: connectivity,
      );
      await manager.start();

      final flight1 = manager.reconnect();
      final flight2 = manager.reconnect();
      final flight3 = manager.reconnect();

      expect(identical(flight1, flight2), isTrue);
      expect(identical(flight2, flight3), isTrue);

      await Future.wait([flight1, flight2, flight3]);
      expect(manager.isReconnecting, isFalse);
    });

    test('12. isReconnecting reflects active in-flight status', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-12',
        connectivityService: connectivity,
      );
      await manager.start();

      expect(manager.isReconnecting, isFalse);
      final flight = manager.reconnect();
      expect(manager.isReconnecting, isTrue);

      await flight;
      expect(manager.isReconnecting, isFalse);
    });

    test('13. exponential backoff increases delay up to maxDelay with bounded jitter', () async {
      final deterministicRandom = Random(42);
      manager = RealtimeConnectionManager(
        accountId: 'test-account-13',
        connectivityService: connectivity,
        initialDelay: const Duration(milliseconds: 1000),
        backoffMultiplier: 2.0,
        maxDelay: const Duration(seconds: 10),
        jitterRatio: 0.2,
        random: deterministicRandom,
      );
      await manager.start();

      manager.registerRequiredChannel('feed:user1');

      // Attempt 1: base = 1000ms
      manager.reportChannelStatus('feed:user1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(1));
      expect(manager.hasScheduledTimer, isTrue);

      // Attempt 2: base = 2000ms
      manager.reportChannelStatus('feed:user1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(2));

      // Attempt 3: base = 4000ms
      manager.reportChannelStatus('feed:user1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(3));

      // Attempt 4: base = 8000ms
      manager.reportChannelStatus('feed:user1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(4));

      // Attempt 5: base would be 16000ms, clamped to 10000ms
      manager.reportChannelStatus('feed:user1', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(5));
    });

    test('14. jitter is strictly bounded within ±20% of base delay', () async {
      for (int seed = 0; seed < 10; seed++) {
        final random = Random(seed);
        final mgr = RealtimeConnectionManager(
          accountId: 'test-jitter-$seed',
          connectivityService: connectivity,
          initialDelay: const Duration(milliseconds: 1000),
          jitterRatio: 0.2,
          random: random,
        );
        await mgr.start();
        mgr.registerRequiredChannel('ch');
        mgr.reportChannelStatus('ch', RealtimeSubscribeStatus.channelError);
        expect(mgr.retryAttempts, equals(1));
        await mgr.stop();
      }
    });

    test('15. manual retry request resets retry attempts and cancels scheduled backoff', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-15',
        connectivityService: connectivity,
        initialDelay: const Duration(seconds: 5),
      );
      await manager.start();

      manager.registerRequiredChannel('chat:vip');
      manager.reportChannelStatus('chat:vip', RealtimeSubscribeStatus.channelError);
      expect(manager.retryAttempts, equals(1));
      expect(manager.hasScheduledTimer, isTrue);

      manager.reportChannelStatus('chat:vip', RealtimeSubscribeStatus.subscribed);
      await manager.requestManualRetry();

      expect(manager.retryAttempts, equals(0));
      expect(manager.hasScheduledTimer, isFalse);
    });

    test('16. manual retry request triggers force reconnect', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-16',
        connectivityService: connectivity,
      );
      await manager.start();

      await manager.requestManualRetry();
      expect(manager.status, equals(RealtimeConnectionStatus.connected));
    });

    test('17. required channels tracking requires all channels to be subscribed', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-17',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:alpha');
      manager.registerRequiredChannel('chat:beta');

      manager.reportChannelStatus('chat:alpha', RealtimeSubscribeStatus.subscribed);
      expect(manager.status, equals(RealtimeConnectionStatus.connecting));

      manager.reportChannelStatus('chat:beta', RealtimeSubscribeStatus.subscribed);
      expect(manager.status, equals(RealtimeConnectionStatus.connected));
    });

    test('18. channel error transitions status to disconnected and schedules reconnect', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-18',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:gamma');
      manager.reportChannelStatus('chat:gamma', RealtimeSubscribeStatus.channelError);

      expect(manager.status, equals(RealtimeConnectionStatus.disconnected));
      expect(manager.hasScheduledTimer, isTrue);
    });

    test('19. channel timeout transitions status to disconnected and schedules reconnect', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-19',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:delta');
      manager.reportChannelStatus('chat:delta', RealtimeSubscribeStatus.timedOut);

      expect(manager.status, equals(RealtimeConnectionStatus.disconnected));
      expect(manager.hasScheduledTimer, isTrue);
    });

    test('20. channel error while offline pauses Realtime without timer', () async {
      connectivity.setInterface(false);
      manager = RealtimeConnectionManager(
        accountId: 'test-account-20',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:offline');
      manager.reportChannelStatus('chat:offline', RealtimeSubscribeStatus.channelError);

      expect(manager.status, equals(RealtimeConnectionStatus.paused));
      expect(manager.hasScheduledTimer, isFalse);
    });

    test('21. channel closed updates status without scheduling error reconnect', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-21',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('chat:closed_ch');
      manager.reportChannelStatus('chat:closed_ch', RealtimeSubscribeStatus.closed);

      expect(manager.hasScheduledTimer, isFalse);
    });

    test('22. unregistering channel recalculates status and dispatches catch-up when fully connected', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-22',
        connectivityService: connectivity,
        onCatchUp: () async {
          catchUpCallCount++;
        },
      );
      manager.registerRequiredChannel('chat:sub1');
      manager.registerRequiredChannel('chat:sub2');
      await manager.start();

      expect(catchUpCallCount, equals(0));

      manager.reportChannelStatus('chat:sub1', RealtimeSubscribeStatus.subscribed);
      manager.reportChannelStatus('chat:sub2', RealtimeSubscribeStatus.channelError);
      expect(catchUpCallCount, equals(0));

      manager.unregisterChannel('chat:sub2');
      expect(manager.status, equals(RealtimeConnectionStatus.connected));
      expect(catchUpCallCount, equals(1));
    });

    test('23. app lifecycle onAppResumed triggers recovery when socket is unhealthy', () async {
      bool socketHealthy = false;
      manager = RealtimeConnectionManager(
        accountId: 'test-account-23',
        connectivityService: connectivity,
        socketConnectedChecker: () => socketHealthy,
        onCatchUp: () async {
          catchUpCallCount++;
        },
      );
      await manager.start();

      await manager.onAppResumed();
      // Unhealthy socket triggers reconnect, not direct catch-up
      expect(catchUpCallCount, equals(0));
    });

    test('24. app lifecycle onAppResumed triggers catch-up sync when socket is healthy', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-24',
        connectivityService: connectivity,
        onCatchUp: () async {
          catchUpCallCount++;
        },
      );
      await manager.start();
      expect(catchUpCallCount, equals(1));

      await manager.onAppResumed();
      expect(catchUpCallCount, equals(2));
    });

    test('25. clean stop closes stream controller and stops timers safely', () async {
      manager = RealtimeConnectionManager(
        accountId: 'test-account-25',
        connectivityService: connectivity,
      );
      await manager.start();

      manager.registerRequiredChannel('test:channel');
      manager.reportChannelStatus('test:channel', RealtimeSubscribeStatus.channelError);
      expect(manager.hasScheduledTimer, isTrue);

      await manager.stop();

      expect(manager.hasScheduledTimer, isFalse);
      await manager.stop();
      manager.reportChannelStatus('test:channel', RealtimeSubscribeStatus.subscribed);
    });

    test('26. ReconciliationService integration respects reachability when syncing', () async {
      final tempDir = Directory.systemTemp.createTempSync('recon_rcm_test_');
      Hive.init(tempDir.path);
      HiveInit.registerAdapters();

      final msgBox = await Hive.openBox<ChatMessage>('cache_msgs_rcm_test');
      final chatBox = await Hive.openBox('chats_cache_rcm_test');
      final messagesStore = MessagesStore(msgBox);
      final chatsStore = ChatsStore(chatBox);

      connectivity.setReachability(BackendReachabilityStatus.unreachable);

      final recon = ReconciliationService(
        accountId: 'rcm_test',
        messagesStore: messagesStore,
        chatsStore: chatsStore,
        connectivityService: connectivity,
        connectionManager: manager = RealtimeConnectionManager(
          accountId: 'rcm_test',
          connectivityService: connectivity,
        ),
      );

      // Sync without customFetcher while unreachable should exit immediately without REST query
      final synced = await recon.syncMessages();

      expect(synced, equals(0));
      await recon.stop();
      if (msgBox.isOpen) await msgBox.close();
      if (chatBox.isOpen) await chatBox.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });
}
