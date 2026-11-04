import 'dart:async';
import 'dart:io';

/// Probes network endpoints to verify actual internet and backend reachability.
///
/// Keeps active network reachability proof distinct from passive interface detection
/// in [ConnectivityService].
class NetworkDiagnostics {
  final Future<bool> Function(String host, int port, Duration timeout)?
  _socketTester;

  const NetworkDiagnostics({
    Future<bool> Function(String host, int port, Duration timeout)?
    socketTester,
  }) : _socketTester = socketTester;

  /// Verifies active internet connectivity by probing a reliable DNS host (default: 8.8.8.8:53).
  Future<bool> checkInternetReachability({
    String host = '8.8.8.8',
    int port = 53,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final socketTester = _socketTester;
    if (socketTester != null) {
      return socketTester(host, port, timeout);
    }

    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifies reachability of the specific Supabase backend endpoint.
  ///
  /// Bounded by [timeout] for both DNS resolution and TCP handshake.
  /// Immediately cleans up socket resources via [Socket.destroy].
  Future<bool> checkEndpointReachability(
    Uri endpoint, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final host = endpoint.host;
    if (host.isEmpty) return false;
    final port = endpoint.hasPort
        ? endpoint.port
        : (endpoint.scheme == 'https' ? 443 : 80);

    final socketTester = _socketTester;
    if (socketTester != null) {
      return socketTester(host, port, timeout);
    }

    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
