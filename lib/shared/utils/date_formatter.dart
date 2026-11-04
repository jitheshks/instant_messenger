// lib/shared/utils/date_formatter.dart

import 'package:intl/intl.dart';
export 'chat_date.dart';

/// Centralized date and time formatting utilities for Instant Messenger.
class DateFormatter {
  DateFormatter._();

  /// Formats a call history date and time timestamp.
  ///
  /// Examples:
  /// - Today: "Today, 4:00 PM"
  /// - Yesterday: "Yesterday, 11:30 AM"
  /// - Older: "10/24/2026, 2:15 PM"
  static String formatCallDateTime(DateTime date, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final localDate = date.toLocal();
    final localNow = current.toLocal();

    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final targetDay = DateTime(localDate.year, localDate.month, localDate.day);

    final timeStr = DateFormat('h:mm a').format(localDate);

    if (targetDay == today) {
      return 'Today, $timeStr';
    } else if (targetDay == yesterday) {
      return 'Yesterday, $timeStr';
    } else {
      return '${localDate.month}/${localDate.day}/${localDate.year}, $timeStr';
    }
  }

  /// Formats duration in seconds into a standard MM:SS or HH:MM:SS string.
  ///
  /// Examples:
  /// - 45 -> "00:45"
  /// - 120 -> "02:00"
  /// - 3665 -> "01:01:05"
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hh = hours.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }

    return '$mm:$ss';
  }
}
