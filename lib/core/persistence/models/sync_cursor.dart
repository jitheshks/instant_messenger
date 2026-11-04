/// Represents a high-watermark synchronization cursor persisted in Hive CE.
class SyncCursor {
  static const int legacyVersion = 1;
  static const int currentVersion = 2;

  final String cursorKey;
  final int lastSyncTimestamp; // Stored in epoch microseconds
  final String? lastSyncId;
  final String? lastSyncIso;
  final int version;

  const SyncCursor({
    required this.cursorKey,
    required this.lastSyncTimestamp,
    this.lastSyncId,
    this.lastSyncIso,
    this.version = currentVersion,
  });

  Map<String, dynamic> toMap() => {
    'version': version,
    'cursorKey': cursorKey,
    'lastSyncTimestamp': lastSyncTimestamp,
    'lastSyncTimestampMicros': lastSyncTimestamp,
    if (lastSyncIso != null) 'lastSyncIso': lastSyncIso,
    if (lastSyncId != null) 'lastSyncId': lastSyncId,
  };

  factory SyncCursor.fromMap(Map m) {
    final version = m['version'] as int?;
    final cursorKey = (m['cursorKey'] as String?) ?? '';
    final syncId = m['lastSyncId'] as String?;

    if (version == null || version == legacyVersion) {
      // Legacy v1 format: timestamp was stored as epoch MILLISECONDS.
      // Must NEVER interpret a legacy millisecond value as microseconds.
      // Explicit format distinction (version == null / 1) ensures unit is never inferred from magnitude alone.
      final dynamic rawTs = m['lastSyncTimestamp'];
      final legacyMs = rawTs is int
          ? rawTs
          : (rawTs is num
                ? rawTs.toInt()
                : int.tryParse(rawTs?.toString() ?? '') ?? 0);
      final micros = legacyMs > 0 ? legacyMs * 1000 : 0;
      final iso = micros > 0
          ? DateTime.fromMicrosecondsSinceEpoch(
              micros,
              isUtc: true,
            ).toIso8601String()
          : null;
      return SyncCursor(
        cursorKey: cursorKey,
        lastSyncTimestamp: micros,
        lastSyncId: syncId,
        lastSyncIso: iso,
        version: currentVersion,
      );
    }

    // Modern v2+ format: timestamp is stored as epoch MICROSECONDS.
    final dynamic rawMicros =
        m['lastSyncTimestampMicros'] ?? m['lastSyncTimestamp'];
    final micros = rawMicros is int
        ? rawMicros
        : (rawMicros is num
              ? rawMicros.toInt()
              : int.tryParse(rawMicros?.toString() ?? '') ?? 0);
    final iso =
        (m['lastSyncIso'] as String?) ??
        (micros > 0
            ? DateTime.fromMicrosecondsSinceEpoch(
                micros,
                isUtc: true,
              ).toIso8601String()
            : null);

    return SyncCursor(
      cursorKey: cursorKey,
      lastSyncTimestamp: micros,
      lastSyncId: syncId,
      lastSyncIso: iso,
      version: version,
    );
  }

  SyncCursor copyWith({
    String? cursorKey,
    int? lastSyncTimestamp,
    String? lastSyncId,
    String? lastSyncIso,
    int? version,
  }) {
    return SyncCursor(
      cursorKey: cursorKey ?? this.cursorKey,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      lastSyncId: lastSyncId ?? this.lastSyncId,
      lastSyncIso: lastSyncIso ?? this.lastSyncIso,
      version: version ?? this.version,
    );
  }
}
