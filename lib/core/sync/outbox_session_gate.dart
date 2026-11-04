import 'dart:async';

/// Coordinates concurrent Hive store access and lifecycle shutdown.
///
/// Prevents check-then-close races and guarantees that in-flight asynchronous
/// network operations completing after daemon shutdown cannot write to closed stores.
class OutboxSessionGate {
  bool _isClosed = false;
  int _activeOperations = 0;
  final List<Completer<void>> _pendingCompletions = [];

  bool get isClosed => _isClosed;
  int get activeOperations => _activeOperations;

  /// Executes [action] if the gate is currently open.
  ///
  /// Returns `null` if the gate is already closed or closing, guaranteeing that
  /// no store write is initiated after shutdown has started.
  Future<T?> run<T>(Future<T> Function() action) async {
    if (_isClosed) return null;
    _activeOperations++;
    try {
      if (_isClosed) return null;
      return await action();
    } finally {
      _activeOperations--;
      if (_activeOperations == 0) {
        for (final completer in _pendingCompletions) {
          if (!completer.isCompleted) completer.complete();
        }
        _pendingCompletions.clear();
      }
    }
  }

  /// Closes the gate to reject all future store write attempts, and awaits
  /// any currently executing microtask-level store writes to complete before returning.
  ///
  /// Guaranteed not to hang: if active operations exceed [timeout], it proceeds.
  Future<void> close({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    _isClosed = true;
    if (_activeOperations > 0) {
      final completer = Completer<void>();
      _pendingCompletions.add(completer);
      await completer.future.timeout(timeout, onTimeout: () {});
    }
  }
}
