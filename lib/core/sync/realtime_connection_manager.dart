import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Explicit connection states for the application's Supabase Realtime layer.
enum RealtimeConnectionStatus {
  /// Connecting or reconnecting the underlying WebSocket transport.
  connecting,

  /// WebSocket is open and required application channels are actively joined.
  connected,

  /// WebSocket is disconnected or channels have errored; backoff reconnect is scheduled.
  disconnected,

  /// Reconnection is temporarily suspended because there is no physical network
  /// interface, or the Supabase backend is explicitly unreachable.
  paused,
}

/// Centralized coordinator for Supabase Realtime WebSocket connection lifecycle,
/// single-flight recovery, bounded exponential backoff with jitter, and catch-up dispatch.
///
/// Eliminates competing 4-second reconnect timers across repositories and services,
/// coordinates with SDK internal rejoins, and bridges Stage 2A reachability detection
/// to ensure clean recovery without reconnect storms or channel leaks.
class RealtimeConnectionManager {
  final String accountId;
  final SupabaseClient? _supabaseClient;
  final ConnectivityService connectivityService;
  final bool Function()? socketConnectedChecker;
  final Future<void> Function()? onCatchUp;

  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final double jitterRatio;
  final Random _random;

  final Set<String> _requiredChannels = {};
  final Map<String, RealtimeSubscribeStatus> _channelStatuses = {};

  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;
  Timer? _reconnectTimer;
  Completer<void>? _reconnectCompleter;
  int _retryAttempts = 0;
  bool _isStopped = false;

  StreamSubscription<NetworkInterfaceStatus>? _connectivitySub;
  StreamSubscription<BackendReachabilityStatus>? _reachabilitySub;
  StreamSubscription<AuthState>? _authSub;

  RealtimeConnectionManager({
    required this.accountId,
    SupabaseClient? supabaseClient,
    ConnectivityService? connectivityService,
    this.socketConnectedChecker,
    this.onCatchUp,
    this.initialDelay = const Duration(milliseconds: 1500),
    this.backoffMultiplier = 1.5,
    this.maxDelay = const Duration(seconds: 60),
    this.jitterRatio = 0.2,
    Random? random,
  }) : _supabaseClient = supabaseClient,
       connectivityService = connectivityService ?? ConnectivityService(),
       _random = random ?? Random() {
    _status = _evaluateStatus();
  }

  SupabaseClient? get _safeSb {
    if (_supabaseClient != null) return _supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get _isSocketConnected {
    if (socketConnectedChecker != null) {
      return socketConnectedChecker!();
    }
    final sb = _safeSb;
    if (sb == null) return true;
    return sb.realtime.isConnected;
  }

  /// Current Realtime connection status.
  RealtimeConnectionStatus get status => _status;

  /// Stream of connection status transitions.
  Stream<RealtimeConnectionStatus> get onStatusChanged =>
      _statusController.stream;

  /// Current retry attempt counter (visible for testing).
  @visibleForTesting
  int get retryAttempts => _retryAttempts;

  /// Whether a reconnect timer is currently scheduled (visible for testing).
  @visibleForTesting
  bool get hasScheduledTimer => _reconnectTimer != null && _reconnectTimer!.isActive;

  /// Whether single-flight reconnection is currently in-flight.
  bool get isReconnecting => _reconnectCompleter != null;

  /// Initializes connectivity listeners, auth stream, and establishes connection.
  Future<void> start() async {
    if (_isStopped) return;

    // 1. Listen to physical network interface transitions
    _connectivitySub = connectivityService.onStatusChanged.listen((status) {
      if (_isStopped) return;
      if (!status.hasInterface) {
        debugPrint(
          '[RealtimeConnectionManager] Network interface lost -> pausing Realtime',
        );
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _updateStatus(RealtimeConnectionStatus.paused);
      } else {
        if (_status == RealtimeConnectionStatus.paused) {
          debugPrint(
            '[RealtimeConnectionManager] Network interface restored -> expediting reconnect',
          );
          _retryAttempts = 0;
          unawaited(reconnect(force: true));
        }
      }
    });

    // 2. Listen to Stage 2A backend reachability transitions
    _reachabilitySub = connectivityService.onReachabilityChanged.listen((
      reachability,
    ) {
      if (_isStopped) return;
      if (reachability == BackendReachabilityStatus.unreachable) {
        debugPrint(
          '[RealtimeConnectionManager] Backend unreachable -> pausing Realtime',
        );
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _updateStatus(RealtimeConnectionStatus.paused);
      } else if (reachability == BackendReachabilityStatus.reachable) {
        debugPrint(
          '[RealtimeConnectionManager] Backend reachable restored -> waking Realtime',
        );
        _retryAttempts = 0;
        unawaited(reconnect());
      }
    });

    // 3. Listen to Supabase auth events
    final sb = _safeSb;
    if (sb != null) {
      try {
        _authSub = sb.auth.onAuthStateChange.listen((data) {
          if (_isStopped) return;
          final event = data.event;
          if (event == AuthChangeEvent.tokenRefreshed) {
            final token = data.session?.accessToken;
            if (token != null) {
              debugPrint(
                '[RealtimeConnectionManager] Token refreshed -> updating socket auth',
              );
              try {
                unawaited(sb.realtime.setAuth(token));
              } catch (_) {}
            }
          } else if (event == AuthChangeEvent.signedIn) {
            debugPrint(
              '[RealtimeConnectionManager] Signed in -> expediting reconnect',
            );
            _retryAttempts = 0;
            unawaited(reconnect(force: true));
          } else if (event == AuthChangeEvent.signedOut) {
            debugPrint('[RealtimeConnectionManager] Signed out -> stopping');
            unawaited(stop());
          }
        });
      } catch (e) {
        debugPrint(
          '[RealtimeConnectionManager] Non-fatal auth listener notice: $e',
        );
      }
    }

    // 4. Initial connection flight
    await reconnect();
  }

  /// Registers a channel topic name as required for application readiness.
  void registerRequiredChannel(String channelName) {
    if (_requiredChannels.add(channelName)) {
      final newStatus = _evaluateStatus();
      if (newStatus == RealtimeConnectionStatus.connected) {
        _onFullyConnected();
      } else {
        _updateStatus(newStatus);
      }
    }
  }

  /// Unregisters a channel topic name.
  void unregisterChannel(String channelName) {
    _requiredChannels.remove(channelName);
    _channelStatuses.remove(channelName);
    final newStatus = _evaluateStatus();
    if (newStatus == RealtimeConnectionStatus.connected) {
      _onFullyConnected();
    } else {
      _updateStatus(newStatus);
    }
  }

  /// Reports a status update from a channel subscription callback.
  void reportChannelStatus(
    String channelName,
    RealtimeSubscribeStatus status, [
    Object? error,
  ]) {
    if (_isStopped) return;

    _channelStatuses[channelName] = status;

    if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      debugPrint(
        '[RealtimeConnectionManager] Channel $channelName reported error ($status): $error',
      );
      // If we are offline or backend is unreachable, pause; otherwise schedule exponential backoff
      if (!connectivityService.hasNetworkInterface ||
          connectivityService.backendReachabilityStatus ==
              BackendReachabilityStatus.unreachable) {
        _updateStatus(RealtimeConnectionStatus.paused);
      } else {
        _scheduleReconnect();
      }
    } else if (status == RealtimeSubscribeStatus.subscribed) {
      debugPrint(
        '[RealtimeConnectionManager] Channel $channelName joined successfully',
      );
      final newStatus = _evaluateStatus();
      if (newStatus == RealtimeConnectionStatus.connected) {
        _onFullyConnected();
      } else {
        _updateStatus(newStatus);
      }
    } else if (status == RealtimeSubscribeStatus.closed) {
      _updateStatus(_evaluateStatus());
    }
  }

  /// Single-flight reconnection workflow.
  ///
  /// Coalesces concurrent calls into the currently executing flight.
  /// When [force] is true, recycles the socket transport to handle network interface switching.
  Future<void> reconnect({bool force = false}) {
    if (_isStopped) return Future.value();

    if (_reconnectCompleter != null) {
      return _reconnectCompleter!.future;
    }

    final completer = Completer<void>();
    _reconnectCompleter = completer;

    () async {
      await Future<void>.delayed(Duration.zero);
      try {
        // 1. Guard against attempting to connect while offline or backend unreachable
        if (!connectivityService.hasNetworkInterface ||
            connectivityService.backendReachabilityStatus ==
                BackendReachabilityStatus.unreachable) {
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _updateStatus(RealtimeConnectionStatus.paused);
          return;
        }

        _updateStatus(RealtimeConnectionStatus.connecting);

        final sb = _safeSb;
        if (sb != null) {
          try {
            if (force && sb.realtime.isConnected) {
              debugPrint(
                '[RealtimeConnectionManager] Force reconnect requested -> recycling socket',
              );
              await sb.realtime.disconnect();
              // ignore: invalid_use_of_internal_member
              await sb.realtime.connect();
            } else if (!sb.realtime.isConnected) {
              debugPrint(
                '[RealtimeConnectionManager] Socket not open -> connecting',
              );
              // ignore: invalid_use_of_internal_member
              await sb.realtime.connect();
            }
          } catch (e) {
            debugPrint(
              '[RealtimeConnectionManager] Socket connection error: $e',
            );
            _scheduleReconnect();
            return;
          }
        }

        final evaluated = _evaluateStatus(ignoreInFlightLock: true);
        if (evaluated == RealtimeConnectionStatus.connected) {
          _onFullyConnected();
        } else {
          // Channels may be in the middle of rejoining (Phoenix protocol)
          _updateStatus(evaluated);
          if (evaluated == RealtimeConnectionStatus.disconnected) {
            _scheduleReconnect();
          }
        }
      } catch (e) {
        debugPrint('[RealtimeConnectionManager] Reconnect error: $e');
      } finally {
        _reconnectCompleter = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }();

    return completer.future;
  }

  /// Triggered when the application returns to foreground.
  ///
  /// Probes socket liveness and initiates controlled recovery if the socket dropped
  /// silently while suspended by the OS.
  Future<void> onAppResumed() async {
    if (_isStopped) return;

    final isSocketOpen = _isSocketConnected;
    final isHealthy = isSocketOpen &&
        _requiredChannels.every(
          (c) => _channelStatuses[c] == RealtimeSubscribeStatus.subscribed,
        );

    if (!isHealthy) {
      debugPrint(
        '[RealtimeConnectionManager] App resumed with unhealthy socket -> triggering recovery',
      );
      await reconnect(force: true);
    } else {
      debugPrint(
        '[RealtimeConnectionManager] App resumed with healthy socket -> triggering catch-up sync',
      );
      if (onCatchUp != null) {
        unawaited(onCatchUp!());
      }
    }
  }

  /// Requests an immediate manual reconnect attempt from the UI.
  ///
  /// Resets backoff attempt counter and immediately dispatches a single-flight reconnect.
  Future<void> requestManualRetry() async {
    if (_isStopped) return;
    debugPrint(
      '[RealtimeConnectionManager] Manual retry requested -> resetting backoff',
    );
    _retryAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await reconnect(force: true);
  }

  void _onFullyConnected() {
    _retryAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _updateStatus(RealtimeConnectionStatus.connected);

    debugPrint(
      '[RealtimeConnectionManager] Realtime fully connected -> dispatching catch-up sync',
    );
    if (onCatchUp != null) {
      unawaited(onCatchUp!());
    }
  }

  void _scheduleReconnect() {
    if (_isStopped) return;

    if (!connectivityService.hasNetworkInterface ||
        connectivityService.backendReachabilityStatus ==
            BackendReachabilityStatus.unreachable) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _updateStatus(RealtimeConnectionStatus.paused);
      return;
    }

    _updateStatus(RealtimeConnectionStatus.disconnected);

    _reconnectTimer?.cancel();

    // Bounded exponential backoff with jitter
    final baseMs = initialDelay.inMilliseconds *
        pow(backoffMultiplier, _retryAttempts).toDouble();
    final clampedBase = min(baseMs, maxDelay.inMilliseconds.toDouble());
    final jitterFactor = (_random.nextDouble() * 2 - 1) * jitterRatio; // -20% to +20%
    final targetDelayMs = (clampedBase * (1.0 + jitterFactor))
        .toInt()
        .clamp(500, maxDelay.inMilliseconds);

    _retryAttempts++;

    debugPrint(
      '[RealtimeConnectionManager] Scheduling reconnect in ${targetDelayMs}ms (attempt $_retryAttempts)',
    );

    _reconnectTimer = Timer(Duration(milliseconds: targetDelayMs), () {
      if (!_isStopped) {
        unawaited(reconnect());
      }
    });
  }

  RealtimeConnectionStatus _evaluateStatus({bool ignoreInFlightLock = false}) {
    if (_isStopped) return RealtimeConnectionStatus.disconnected;

    if (!connectivityService.hasNetworkInterface ||
        connectivityService.backendReachabilityStatus ==
            BackendReachabilityStatus.unreachable) {
      return RealtimeConnectionStatus.paused;
    }

    if (!ignoreInFlightLock && _reconnectCompleter != null) {
      return RealtimeConnectionStatus.connecting;
    }

    if (!_isSocketConnected) {
      return RealtimeConnectionStatus.disconnected;
    }

    if (_requiredChannels.isNotEmpty) {
      final allSubscribed = _requiredChannels.every(
        (ch) => _channelStatuses[ch] == RealtimeSubscribeStatus.subscribed,
      );
      if (allSubscribed) {
        return RealtimeConnectionStatus.connected;
      }
      final anyError = _requiredChannels.any(
        (ch) =>
            _channelStatuses[ch] == RealtimeSubscribeStatus.channelError ||
            _channelStatuses[ch] == RealtimeSubscribeStatus.timedOut,
      );
      if (anyError) {
        return RealtimeConnectionStatus.disconnected;
      }
      return RealtimeConnectionStatus.connecting;
    }

    return RealtimeConnectionStatus.connected;
  }

  void _updateStatus(RealtimeConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
    }
  }

  /// Stops the connection manager, cancels background timers, unbinds listeners,
  /// and safely closes the status stream.
  Future<void> stop() async {
    if (_isStopped) return;
    _isStopped = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_connectivitySub != null) {
      await _connectivitySub!.cancel();
      _connectivitySub = null;
    }
    if (_reachabilitySub != null) {
      await _reachabilitySub!.cancel();
      _reachabilitySub = null;
    }
    if (_authSub != null) {
      await _authSub!.cancel();
      _authSub = null;
    }

    _requiredChannels.clear();
    _channelStatuses.clear();

    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }

  void dispose() {
    unawaited(stop());
  }
}
