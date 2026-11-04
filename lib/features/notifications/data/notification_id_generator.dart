import 'dart:convert';

/// Centralized, deterministic notification ID generator for Android and iOS local notifications.
///
/// Ensures all generated notification IDs strictly conform to the 31-bit positive
/// signed integer range [0, 2147483647] (0 to 0x7FFFFFFF) required by Android's
/// `NotificationManager.notify(int id, ...)` and `flutter_local_notifications`.
class NotificationIdGenerator {
  /// Minimum valid Android/iOS notification ID.
  static const int minId = 0;

  /// Maximum valid 31-bit signed positive integer (2,147,483,647).
  static const int maxId = 0x7FFFFFFF;

  /// 32-bit FNV-1a offset basis: 2166136261 (0x811c9dc5).
  static const int _fnvOffsetBasis32 = 0x811c9dc5;

  /// 32-bit FNV-1a prime: 16777619 (0x01000193).
  static const int _fnvPrime32 = 0x01000193;

  /// Computes a standard 32-bit FNV-1a hash over the UTF-8 bytes of [input].
  ///
  /// This hash is platform-independent, CPU architecture-independent, and deterministic
  /// across application restarts and Dart VM versions (unlike `Object.hashCode`).
  static int fnv1a32(String input) {
    final bytes = utf8.encode(input);
    int hash = _fnvOffsetBasis32;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * _fnvPrime32) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Converts any string into a deterministic positive 31-bit integer in [0, 0x7FFFFFFF].
  static int hashTo31Bit(String input) {
    final hash32 = fnv1a32(input);
    final id31 = hash32 & maxId;
    return id31;
  }

  /// Generates a deterministic notification ID for a message notification.
  ///
  /// Priority:
  /// 1. If [messageId] is non-null and non-empty, computes a deterministic hash of `"msg_${messageId.trim()}"`.
  ///    This allows notifications for the same message to be updated in-place rather than duplicating.
  /// 2. Fallback: If [messageId] is null or empty, computes a deterministic hash using
  ///    `"fallback_${chatId.trim()}_${fallbackTimestampMs ?? DateTime.now().microsecondsSinceEpoch}"`.
  ///    Even when fallback timestamps are arbitrarily large (e.g., 64-bit microsecond integers),
  ///    the resulting ID is guaranteed to be within [0, 0x7FFFFFFF].
  static int generateMessageNotificationId({
    required String chatId,
    String? messageId,
    int? fallbackTimestampMs,
  }) {
    final cleanMsgId = messageId?.trim();
    final cleanChatId = chatId.trim();

    final String key;
    if (cleanMsgId != null && cleanMsgId.isNotEmpty) {
      key = 'msg_$cleanMsgId';
    } else {
      final ts = fallbackTimestampMs ?? DateTime.now().microsecondsSinceEpoch;
      key = 'fallback_${cleanChatId}_$ts';
    }

    final id = hashTo31Bit(key);
    validateNotificationId(id);
    return id;
  }

  /// Generates a deterministic notification ID for an Android group summary notification.
  ///
  /// Uses the prefix `"summary_"` to ensure that group summary IDs never collide with
  /// message notification IDs for the same chat thread.
  static int generateGroupSummaryNotificationId(String chatId) {
    final cleanChatId = chatId.trim();
    final key = 'summary_$cleanChatId';
    final id = hashTo31Bit(key);
    validateNotificationId(id);
    return id;
  }

  /// Validates that an ID falls within the positive 31-bit integer range [0, 2147483647].
  static bool isValidNotificationId(int id) {
    return id >= minId && id <= maxId;
  }

  /// Validates the notification ID, throwing an [ArgumentError] if it violates bounds.
  static void validateNotificationId(int id) {
    if (!isValidNotificationId(id)) {
      throw ArgumentError(
        'Invalid notification ID ($id): must fit within 31-bit positive integer range [$minId, $maxId].',
      );
    }
  }
}
