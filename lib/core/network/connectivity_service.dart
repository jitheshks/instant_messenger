import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/network/network_diagnostics.dart';

/// Representation of local network interface technologies.
enum NetworkInterfaceType {
  none,
  wifi,
  cellular,
  ethernet,
  vpn,
  bluetooth,
  other,
}

/// Representation of remote backend reachability status.
enum BackendReachabilityStatus {
  unknown,
  reachable,
  unreachable,
}

/// Status of the device's local network adapters.
///
/// NOTE: Having an active network interface does NOT guarantee that the
/// internet is reachable or that remote servers (e.g. Supabase) are reachable.
class NetworkInterfaceStatus {
  final List<NetworkInterfaceType> activeInterfaces;

  const NetworkInterfaceStatus(this.activeInterfaces);

  /// True if at least one active network interface is present.
  bool get hasInterface =>
      activeInterfaces.isNotEmpty &&
      !activeInterfaces.every((t) => t == NetworkInterfaceType.none);

  bool get isWifi => activeInterfaces.contains(NetworkInterfaceType.wifi);
  bool get isCellular =>
      activeInterfaces.contains(NetworkInterfaceType.cellular);
  bool get isEthernet =>
      activeInterfaces.contains(NetworkInterfaceType.ethernet);

  @override
  String toString() =>
      'NetworkInterfaceStatus(hasInterface: $hasInterface, interfaces: $activeInterfaces)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkInterfaceStatus &&
          _listEquals(activeInterfaces, other.activeInterfaces);

  @override
  int get hashCode => Object.hashAll(activeInterfaces);

  static bool _listEquals(
    List<NetworkInterfaceType> a,
    List<NetworkInterfaceType> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Observes physical network interface connectivity states on the device and
/// coordinates controlled, non-overlapping reachability verification to the backend.
///
/// Strict Architectural Boundary:
/// - [hasNetworkInterface] reflects physical/radio adapter status (Wi-Fi, cellular, ethernet).
/// - [isBackendReachable] reflects active host reachability to Supabase backend API.
/// - The reachability probe is debounced, bounded, rate-limited, and never polls continuously.
class ConnectivityService {
  final Connectivity _connectivity;
  final NetworkDiagnostics _networkDiagnostics;
  final Uri? _backendEndpoint;
  final Uri? Function()? _backendEndpointProvider;
  final Duration _minProbeInterval;
  final Duration _probeTimeout;
  final bool _enableControlledRetries;

  StreamController<NetworkInterfaceStatus>? _interfaceController;
  StreamController<BackendReachabilityStatus>? _reachabilityController;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkInterfaceStatus _lastKnownStatus = const NetworkInterfaceStatus([
    NetworkInterfaceType.none,
  ]);
  BackendReachabilityStatus _backendReachability =
      BackendReachabilityStatus.unknown;

  Future<BackendReachabilityStatus>? _ongoingProbe;
  DateTime? _lastProbeTime;
  Timer? _probeRetryTimer;
  int _consecutiveProbeFailures = 0;
  static const int _maxProbeRetries = 2;

  ConnectivityService({
    Connectivity? connectivity,
    NetworkDiagnostics? networkDiagnostics,
    Uri? backendEndpoint,
    Uri? Function()? backendEndpointProvider,
    Duration minProbeInterval = const Duration(seconds: 3),
    Duration probeTimeout = const Duration(seconds: 4),
    bool enableControlledRetries = true,
  })  : _connectivity = connectivity ?? Connectivity(),
        _networkDiagnostics = networkDiagnostics ?? const NetworkDiagnostics(),
        _backendEndpoint = backendEndpoint,
        _backendEndpointProvider = backendEndpointProvider,
        _minProbeInterval = minProbeInterval,
        _probeTimeout = probeTimeout,
        _enableControlledRetries = enableControlledRetries;

  /// The most recent cached network interface status.
  NetworkInterfaceStatus get lastKnownStatus => _lastKnownStatus;

  /// Whether any local network interface is currently active.
  ///
  /// CAUTION: Returns true if WiFi or cellular is connected, even if the upstream
  /// internet route or Supabase backend is down.
  bool get hasNetworkInterface => _lastKnownStatus.hasInterface;

  /// Whether the backend was verified to be reachable.
  bool get isBackendReachable =>
      _backendReachability == BackendReachabilityStatus.reachable;

  /// Detailed backend reachability status (unknown, reachable, unreachable).
  BackendReachabilityStatus get backendReachabilityStatus =>
      _backendReachability;

  /// Stream of network interface status changes.
  Stream<NetworkInterfaceStatus> get onStatusChanged {
    _interfaceController ??= StreamController<NetworkInterfaceStatus>.broadcast(
      onListen: _startListening,
      onCancel: _stopListeningIfEmpty,
    );
    return _interfaceController!.stream;
  }

  /// Stream of backend reachability status changes.
  Stream<BackendReachabilityStatus> get onReachabilityChanged {
    _reachabilityController ??=
        StreamController<BackendReachabilityStatus>.broadcast(
      onListen: _startListening,
      onCancel: _stopListeningIfEmpty,
    );
    return _reachabilityController!.stream;
  }

  /// Polls the current physical network interface state.
  Future<NetworkInterfaceStatus> checkStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final status = _mapResults(results);
      _lastKnownStatus = status;

      if (!status.hasInterface) {
        _probeRetryTimer?.cancel();
        _probeRetryTimer = null;
        _updateReachability(BackendReachabilityStatus.unreachable);
      } else {
        unawaited(checkBackendReachability());
      }

      return status;
    } catch (_) {
      const status = NetworkInterfaceStatus([NetworkInterfaceType.none]);
      _lastKnownStatus = status;
      _updateReachability(BackendReachabilityStatus.unreachable);
      return status;
    }
  }

  /// Probes the Supabase backend endpoint to verify actual reachability.
  ///
  /// Guarantees:
  /// - Bounded timeout (default: 4 seconds).
  /// - Non-overlapping: concurrent calls return the existing probe future.
  /// - Rate-limited / debounced: respects [_minProbeInterval] unless [force] is true.
  /// - If [hasNetworkInterface] is false, immediately resolves to unreachable without opening sockets.
  /// - When a probe fails while interface is active, schedules controlled backoff retries (up to 2).
  /// - Does not continuously poll.
  Future<BackendReachabilityStatus> checkBackendReachability({
    bool force = false,
  }) async {
    // 1. If physical interface is disconnected, backend is immediately unreachable
    if (!hasNetworkInterface) {
      _probeRetryTimer?.cancel();
      _probeRetryTimer = null;
      _updateReachability(BackendReachabilityStatus.unreachable);
      return BackendReachabilityStatus.unreachable;
    }

    // 2. Return ongoing probe if one is already running (prevents overlapping requests)
    if (_ongoingProbe != null) {
      return _ongoingProbe!;
    }

    // 3. Debounce / rate-limit if recently probed and not forced
    if (!force && _lastProbeTime != null) {
      final elapsed = DateTime.now().difference(_lastProbeTime!);
      if (elapsed < _minProbeInterval) {
        return _backendReachability;
      }
    }

    final completer = Completer<BackendReachabilityStatus>();
    _ongoingProbe = completer.future;

    try {
      final endpoint = _resolveEndpoint();
      if (endpoint == null || endpoint.host.isEmpty) {
        _updateReachability(BackendReachabilityStatus.unknown);
        completer.complete(_backendReachability);
        return _backendReachability;
      }

      final isReachable = await _networkDiagnostics.checkEndpointReachability(
        endpoint,
        timeout: _probeTimeout,
      );

      _lastProbeTime = DateTime.now();

      final newStatus = isReachable
          ? BackendReachabilityStatus.reachable
          : BackendReachabilityStatus.unreachable;

      _updateReachability(newStatus);

      if (isReachable) {
        _consecutiveProbeFailures = 0;
        _probeRetryTimer?.cancel();
        _probeRetryTimer = null;
      } else {
        _scheduleControlledRetry();
      }

      completer.complete(newStatus);
      return newStatus;
    } catch (_) {
      _lastProbeTime = DateTime.now();
      _updateReachability(BackendReachabilityStatus.unreachable);
      _scheduleControlledRetry();
      completer.complete(BackendReachabilityStatus.unreachable);
      return BackendReachabilityStatus.unreachable;
    } finally {
      _ongoingProbe = null;
    }
  }

  void _scheduleControlledRetry() {
    _probeRetryTimer?.cancel();
    _probeRetryTimer = null;

    if (!hasNetworkInterface || !_enableControlledRetries) return;

    if (_consecutiveProbeFailures < _maxProbeRetries) {
      _consecutiveProbeFailures++;
      // Controlled backoff: attempt 1 -> 4s, attempt 2 -> 8s
      final delaySeconds = 4 * _consecutiveProbeFailures;
      _probeRetryTimer = Timer(Duration(seconds: delaySeconds), () {
        if (hasNetworkInterface) {
          unawaited(checkBackendReachability());
        }
      });
    }
  }

  /// Cancels any scheduled retry timers immediately.
  void cancelPendingTimers() {
    _probeRetryTimer?.cancel();
    _probeRetryTimer = null;
  }

  /// Manually sets backend reachability status for unit and widget tests.
  @visibleForTesting
  void updateBackendReachabilityForTesting(BackendReachabilityStatus status) {
    _updateReachability(status);
  }

  void _updateReachability(BackendReachabilityStatus status) {
    if (_backendReachability != status) {
      _backendReachability = status;
      if (_reachabilityController != null &&
          !_reachabilityController!.isClosed) {
        _reachabilityController!.add(status);
      }
    }
  }

  Uri? _resolveEndpoint() {
    if (_backendEndpoint != null) return _backendEndpoint;
    final provider = _backendEndpointProvider;
    if (provider != null) {
      final ep = provider();
      if (ep != null) return ep;
    }
    final url = SupabaseConfig.configuredUrl;
    if (url != null && url.trim().isNotEmpty) {
      return Uri.tryParse(url.trim());
    }
    return null;
  }

  void _startListening() {
    if (_subscription != null) return;
    try {
      _subscription = _connectivity.onConnectivityChanged.listen(
        _onConnectivityChanged,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final status = _mapResults(results);
    _lastKnownStatus = status;

    if (_interfaceController != null && !_interfaceController!.isClosed) {
      _interfaceController!.add(status);
    }

    if (!status.hasInterface) {
      _probeRetryTimer?.cancel();
      _probeRetryTimer = null;
      _consecutiveProbeFailures = 0;
      _updateReachability(BackendReachabilityStatus.unreachable);
    } else {
      // Interface appeared or changed (e.g. offline -> online, cellular -> wifi)
      _consecutiveProbeFailures = 0;
      _probeRetryTimer?.cancel();
      _probeRetryTimer = null;
      // Re-run reachability probe on interface change
      unawaited(checkBackendReachability(force: true));
    }
  }

  void _stopListeningIfEmpty() {
    final hasInterfaceListeners =
        _interfaceController != null && _interfaceController!.hasListener;
    final hasReachabilityListeners =
        _reachabilityController != null && _reachabilityController!.hasListener;

    if (!hasInterfaceListeners && !hasReachabilityListeners) {
      _stopListening();
    }
  }

  void _stopListening() {
    try {
      _subscription?.cancel();
    } catch (_) {}
    _subscription = null;
  }

  @visibleForTesting
  void setBackendReachabilityForTesting(BackendReachabilityStatus status) {
    _updateReachability(status);
  }

  void dispose() {
    _probeRetryTimer?.cancel();
    _probeRetryTimer = null;
    _stopListening();
    _interfaceController?.close();
    _interfaceController = null;
    _reachabilityController?.close();
    _reachabilityController = null;
  }

  NetworkInterfaceStatus _mapResults(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return const NetworkInterfaceStatus([NetworkInterfaceType.none]);
    }

    final mapped = results.map((r) {
      switch (r) {
        case ConnectivityResult.wifi:
          return NetworkInterfaceType.wifi;
        case ConnectivityResult.mobile:
          return NetworkInterfaceType.cellular;
        case ConnectivityResult.ethernet:
          return NetworkInterfaceType.ethernet;
        case ConnectivityResult.vpn:
          return NetworkInterfaceType.vpn;
        case ConnectivityResult.bluetooth:
          return NetworkInterfaceType.bluetooth;
        case ConnectivityResult.satellite:
        case ConnectivityResult.other:
          return NetworkInterfaceType.other;
        case ConnectivityResult.none:
          return NetworkInterfaceType.none;
      }
    }).toList();

    return NetworkInterfaceStatus(mapped);
  }
}
