import 'package:hive/hive.dart';
import '../models/sync_cursor.dart';

/// Manages synchronization cursors (high-watermarks) in Hive CE.
class SyncCursorsStore {
  final Box _box;

  SyncCursorsStore(this._box);

  Box get box => _box;

  Future<void> setCursor(
    String cursorKey,
    int timestampMicros, {
    String? syncId,
    String? isoString,
  }) async {
    final iso =
        isoString ??
        (timestampMicros > 0
            ? DateTime.fromMicrosecondsSinceEpoch(
                timestampMicros,
                isUtc: true,
              ).toIso8601String()
            : null);
    final cursor = SyncCursor(
      cursorKey: cursorKey,
      lastSyncTimestamp: timestampMicros,
      lastSyncId: syncId,
      lastSyncIso: iso,
      version: SyncCursor.currentVersion,
    );
    await _box.put(cursorKey, cursor.toMap());
  }

  SyncCursor? getCursor(String cursorKey) {
    final raw = _box.get(cursorKey);
    if (raw is Map) {
      try {
        return SyncCursor.fromMap(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Explicitly migrates a legacy v1 (millisecond) cursor to v2 (microsecond) format.
  /// Preserves account isolation, cursor key, and last sync position.
  Future<SyncCursor?> migrateCursorIfNeeded(String cursorKey) async {
    final raw = _box.get(cursorKey);
    if (raw is Map) {
      try {
        final version = raw['version'] as int?;
        if (version == null || version == SyncCursor.legacyVersion) {
          final migrated = SyncCursor.fromMap(raw);
          await _box.put(cursorKey, migrated.toMap());
          return migrated;
        }
        return SyncCursor.fromMap(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Migrates all un-versioned or legacy v1 cursors within this account-scoped box.
  /// Returns the count of successfully migrated cursors.
  Future<int> migrateAllLegacyCursors() async {
    int migratedCount = 0;
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        final version = raw['version'] as int?;
        if (version == null || version == SyncCursor.legacyVersion) {
          try {
            final migrated = SyncCursor.fromMap(raw);
            await _box.put(key, migrated.toMap());
            migratedCount++;
          } catch (_) {}
        }
      }
    }
    return migratedCount;
  }

  Future<void> deleteCursor(String cursorKey) async {
    await _box.delete(cursorKey);
  }

  Map<String, SyncCursor> getAll() {
    final map = <String, SyncCursor>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          map[key.toString()] = SyncCursor.fromMap(raw);
        } catch (_) {}
      }
    }
    return map;
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
