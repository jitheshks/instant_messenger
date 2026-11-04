import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/network/network_diagnostics.dart';

class FakeConnectivity implements Connectivity {
  List<ConnectivityResult> currentResults = [ConnectivityResult.none];
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

void main() {
  group('ConnectivityService & NetworkDiagnostics Tests', () {
    late FakeConnectivity fakeConnectivity;
    late ConnectivityService service;

    setUp(() {
      fakeConnectivity = FakeConnectivity();
      service = ConnectivityService(connectivity: fakeConnectivity);
    });

    tearDown(() {
      service.dispose();
    });

    test(
      'checkStatus correctly maps wifi interface and sets hasNetworkInterface true',
      () async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];

        final status = await service.checkStatus();

        expect(status.hasInterface, isTrue);
        expect(status.isWifi, isTrue);
        expect(status.isCellular, isFalse);
        expect(status.activeInterfaces, [NetworkInterfaceType.wifi]);
        expect(service.hasNetworkInterface, isTrue);
      },
    );

    test(
      'checkStatus correctly identifies when no network interface is active',
      () async {
        fakeConnectivity.currentResults = [ConnectivityResult.none];

        final status = await service.checkStatus();

        expect(status.hasInterface, isFalse);
        expect(status.activeInterfaces, [NetworkInterfaceType.none]);
        expect(service.hasNetworkInterface, isFalse);
      },
    );

    test(
      'checkStatus handles cellular and multi-interface scenarios',
      () async {
        fakeConnectivity.currentResults = [
          ConnectivityResult.mobile,
          ConnectivityResult.vpn,
        ];

        final status = await service.checkStatus();

        expect(status.hasInterface, isTrue);
        expect(status.isCellular, isTrue);
        expect(status.activeInterfaces, [
          NetworkInterfaceType.cellular,
          NetworkInterfaceType.vpn,
        ]);
      },
    );

    test(
      'onStatusChanged stream emits new network interface status on transitions',
      () async {
        final emitted = <NetworkInterfaceStatus>[];
        final sub = service.onStatusChanged.listen(emitted.add);

        fakeConnectivity.controller.add([ConnectivityResult.wifi]);
        fakeConnectivity.controller.add([ConnectivityResult.none]);
        fakeConnectivity.controller.add([ConnectivityResult.mobile]);

        await Future<void>.delayed(Duration.zero);

        expect(emitted.length, 3);
        expect(emitted[0].isWifi, isTrue);
        expect(emitted[1].hasInterface, isFalse);
        expect(emitted[2].isCellular, isTrue);

        await sub.cancel();
      },
    );

    test(
      'NetworkDiagnostics maintains strict separation from passive connectivity detection',
      () async {
        // Passive service reports active interface (e.g. WiFi connected to a router)
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        final status = await service.checkStatus();
        expect(status.hasInterface, isTrue);

        // Active diagnostics test reachability (e.g. router has NO internet access)
        final diagnosticsOffline = NetworkDiagnostics(
          socketTester: (host, port, timeout) async => false,
        );
        final isReachable =
            await diagnosticsOffline.checkInternetReachability();
        expect(isReachable, isFalse);

        // Active diagnostics test when internet is proven reachable
        final diagnosticsOnline = NetworkDiagnostics(
          socketTester: (host, port, timeout) async => true,
        );
        final isOnline = await diagnosticsOnline.checkInternetReachability();
        expect(isOnline, isTrue);

        // Backend endpoint reachability verification
        final supabaseUri = Uri.parse('https://example.supabase.co');
        final canReachBackend =
            await diagnosticsOnline.checkEndpointReachability(supabaseUri);
        expect(canReachBackend, isTrue);
      },
    );

    test(
      'checkBackendReachability verifies backend reachability when endpoint is reachable',
      () async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async => true,
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();
        expect(reachabilityService.hasNetworkInterface, isTrue);

        final res = await reachabilityService.checkBackendReachability();
        expect(res, BackendReachabilityStatus.reachable);
        expect(reachabilityService.isBackendReachable, isTrue);
        expect(
          reachabilityService.backendReachabilityStatus,
          BackendReachabilityStatus.reachable,
        );

        reachabilityService.dispose();
      },
    );

    test(
      'checkBackendReachability identifies backend unreachable when socket fails on active Wi-Fi',
      () async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async => false,
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();
        expect(reachabilityService.hasNetworkInterface, isTrue);

        final res = await reachabilityService.checkBackendReachability();
        expect(res, BackendReachabilityStatus.unreachable);
        expect(reachabilityService.isBackendReachable, isFalse);
        expect(
          reachabilityService.backendReachabilityStatus,
          BackendReachabilityStatus.unreachable,
        );

        reachabilityService.dispose();
      },
    );

    test(
      'No network interface immediately marks backend unreachable without socket probe',
      () async {
        int probeCount = 0;
        fakeConnectivity.currentResults = [ConnectivityResult.none];
        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async {
              probeCount++;
              return true;
            },
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();
        expect(reachabilityService.hasNetworkInterface, isFalse);

        final res = await reachabilityService.checkBackendReachability();
        expect(res, BackendReachabilityStatus.unreachable);
        expect(probeCount, 0); // No socket opened!

        reachabilityService.dispose();
      },
    );

    test(
      'Concurrent calls to checkBackendReachability share ongoing probe and do not overlap',
      () async {
        int probeCount = 0;
        final completer = Completer<bool>();
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];

        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async {
              probeCount++;
              return completer.future;
            },
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();

        final f1 = reachabilityService.checkBackendReachability(force: true);
        final f2 = reachabilityService.checkBackendReachability(force: true);
        final f3 = reachabilityService.checkBackendReachability(force: true);

        completer.complete(true);

        final r1 = await f1;
        final r2 = await f2;
        final r3 = await f3;

        expect(probeCount, 1); // Only 1 socket was connected!
        expect(r1, BackendReachabilityStatus.reachable);
        expect(r2, BackendReachabilityStatus.reachable);
        expect(r3, BackendReachabilityStatus.reachable);

        reachabilityService.dispose();
      },
    );

    test(
      'Debounces probe when called within minProbeInterval unless force is true',
      () async {
        int probeCount = 0;
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];

        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          minProbeInterval: const Duration(seconds: 2),
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async {
              probeCount++;
              return true;
            },
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();
        expect(probeCount, 1);

        // Within minProbeInterval: should debounce without socket connect
        await reachabilityService.checkBackendReachability();
        expect(probeCount, 1);

        // Forced: bypasses rate limiting
        await reachabilityService.checkBackendReachability(force: true);
        expect(probeCount, 2);

        reachabilityService.dispose();
      },
    );

    test(
      'Probe timeout and socket exception handled safely without throwing',
      () async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];

        final reachabilityService = ConnectivityService(
          connectivity: fakeConnectivity,
          probeTimeout: const Duration(milliseconds: 50),
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (host, port, timeout) async {
              throw const SocketException('Network is unreachable (errno 101)');
            },
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        await reachabilityService.checkStatus();

        final res =
            await reachabilityService.checkBackendReachability(force: true);
        expect(res, BackendReachabilityStatus.unreachable);
        expect(reachabilityService.isBackendReachable, isFalse);

        reachabilityService.dispose();
      },
    );
  });
}
