import 'package:hive/hive.dart';
import '../models/outbox_entry.dart';

/// Manages durable outbox mutations and retry scheduling in Hive CE.
class OutboxStore {
  final Box _box;

  OutboxStore(this._box);

  Box get box => _box;

  Future<void> enqueue(OutboxEntry entry) async {
    await _box.put(entry.id, entry.toMap());
  }

  OutboxEntry? getById(String id) {
    final raw = _box.get(id);
    if (raw is Map) return OutboxEntry.fromMap(raw);
    return null;
  }

  /// Retrieves queued mutations scheduled to execute at or before [maxNextAttemptAt],
  /// sorted in ascending order of their scheduled time.
  List<OutboxEntry> getScheduled(DateTime maxNextAttemptAt, {int limit = 20}) {
    final entries = <OutboxEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          final entry = OutboxEntry.fromMap(raw);
          if (entry.state == 'queued' &&
              (entry.nextAttemptAt.isBefore(maxNextAttemptAt) ||
                  entry.nextAttemptAt.isAtSameMomentAs(maxNextAttemptAt))) {
            entries.add(entry);
          }
        } catch (_) {}
      }
    }

    entries.sort((a, b) => a.nextAttemptAt.compareTo(b.nextAttemptAt));
    if (entries.length > limit) {
      return entries.sublist(0, limit);
    }
    return entries;
  }

  Future<void> updateState(
    String id,
    String state, {
    DateTime? nextAttemptAt,
    int? retryCount,
  }) async {
    final existing = getById(id);
    if (existing != null) {
      final updated = existing.copyWith(
        state: state,
        nextAttemptAt: nextAttemptAt,
        retryCount: retryCount,
      );
      await _box.put(id, updated.toMap());
    }
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
  }

  List<OutboxEntry> getAll() {
    final list = <OutboxEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          list.add(OutboxEntry.fromMap(raw));
        } catch (_) {}
      }
    }
    return list;
  }

  /// Resets scheduled time to [now] for all currently queued mutations
  /// so they are eligible for immediate dispatch upon connectivity/reachability restoration.
  Future<int> resetScheduledForQueued([DateTime? now]) async {
    final effectiveNow = now ?? DateTime.now();
    var resetCount = 0;
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          final entry = OutboxEntry.fromMap(raw);
          if (entry.state == 'queued' &&
              entry.nextAttemptAt.isAfter(effectiveNow)) {
            await _box.put(
              entry.id,
              entry.copyWith(nextAttemptAt: effectiveNow).toMap(),
            );
            resetCount++;
          }
        } catch (_) {}
      }
    }
    return resetCount;
  }

  /// Recovers abandoned or crashed in-flight mutations upon startup/reopening.
  ///
  /// Resets mutations marked 'in_flight' back to 'queued' regardless of previous
  /// retry count, so transient operations interrupted by application termination
  /// or crash are safely resumed.
  /// Returns the number of mutations restored to 'queued'.
  Future<int> recoverInFlight({int? maxRetries}) async {
    var recoveredCount = 0;
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          final entry = OutboxEntry.fromMap(raw);
          if (entry.state == 'in_flight') {
            await _box.put(
              entry.id,
              entry
                  .copyWith(state: 'queued', nextAttemptAt: DateTime.now())
                  .toMap(),
            );
            recoveredCount++;
          }
        } catch (_) {}
      }
    }
    return recoveredCount;
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
