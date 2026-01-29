import 'package:hive/hive.dart';
import '../models/chat_message.dart';

/// OutboxMeta
/// ------------------------------------------------------------
/// Holds BOTH:
/// 1️⃣ Retry/backoff metadata
/// 2️⃣ Media upload metadata (used by BackgroundUploadWorker)
///
/// This is intentionally merged to avoid split responsibility.
class OutboxMeta {
  /// 🔑 Local message id (same as ChatMessage.id)
  final String messageId;

  /// 🔑 Chat context
  final String chatId;

  /// 🔑 Local file path (compressed media)
  final String filePath;

  /// 🔑 Media type (image / video / audio)
  final MediaKind mediaKind;

  /// Optional (future-proof: groups)
  final bool isGroup;

  /// Retry metadata
  final int retryCount;
  final DateTime nextAttemptAt;

  const OutboxMeta({
    required this.messageId,
    required this.chatId,
    required this.filePath,
    required this.mediaKind,
    this.isGroup = false,
    required this.retryCount,
    required this.nextAttemptAt,
  });

  // ------------------------------------------------------------
  // COPY
  // ------------------------------------------------------------

  OutboxMeta copyWith({
    int? retryCount,
    DateTime? nextAttemptAt,
  }) {
    return OutboxMeta(
      messageId: messageId,
      chatId: chatId,
      filePath: filePath,
      mediaKind: mediaKind,
      isGroup: isGroup,
      retryCount: retryCount ?? this.retryCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    );
  }

  // ------------------------------------------------------------
  // SERIALIZATION (Hive-safe Map)
  // ------------------------------------------------------------

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'chatId': chatId,
        'filePath': filePath,
        'mediaKind': mediaKind.name,
        'isGroup': isGroup,
        'retryCount': retryCount,
        'nextAttemptAt': nextAttemptAt.millisecondsSinceEpoch,
      };

  static OutboxMeta fromMap(Map m) {
    return OutboxMeta(
      messageId: m['messageId'] as String,
      chatId: m['chatId'] as String,
      filePath: m['filePath'] as String,
      mediaKind: MediaKind.values.firstWhere(
        (e) => e.name == m['mediaKind'],
        orElse: () => MediaKind.image,
      ),
      isGroup: (m['isGroup'] as bool?) ?? false,
      retryCount: (m['retryCount'] as int?) ?? 0,
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
        (m['nextAttemptAt'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

/// ------------------------------------------------------------
/// OutboxMetaStore (Hive wrapper)
/// ------------------------------------------------------------
class OutboxMetaStore {
  final Box _box;

  OutboxMetaStore(this._box);

  OutboxMeta? get(String messageId) {
    final raw = _box.get(messageId);
    if (raw is Map) return OutboxMeta.fromMap(raw);
    return null;
  }

  Future<void> put(OutboxMeta meta) async {
    await _box.put(meta.messageId, meta.toMap());
  }

  Future<void> delete(String messageId) async {
    await _box.delete(messageId);
  }

  /// Cleanup orphaned meta entries (safe to call on app start)
  Future<void> sweepInvalidKeys(Iterable<String> validIds) async {
    final valid = validIds.map((e) => e.toString()).toSet();
    final toDelete = <dynamic>[];

    for (final key in _box.keys) {
      if (!valid.contains(key.toString())) {
        toDelete.add(key);
      }
    }

    if (toDelete.isNotEmpty) {
      await _box.deleteAll(toDelete);
    }
  }

  DateTime? getNextAttemptAt(String messageId) {
    return get(messageId)?.nextAttemptAt;
  }
}
