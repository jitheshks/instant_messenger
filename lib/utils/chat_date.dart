import 'package:intl/intl.dart';
import 'package:instant_messenger/models/user_presence.dart';

/// ------------------------------------------------------------
/// CHAT DATE HELPERS
/// ------------------------------------------------------------

/// Returns a human-friendly label for chat message grouping
/// Examples:
/// Today, Yesterday, Monday, 12 Jan 2025
String chatDateLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = today.difference(d).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff <= 6) return _weekdayName(d.weekday);

  return '${date.day} ${_monthName(date.month)} ${date.year}';
}

/// Stable key for grouping messages by day
/// Format: YYYY-MM-DD
String dayKey(DateTime dt) {
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$mm-$dd';
}

String _weekdayName(int w) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][w - 1];

String _monthName(int m) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][m - 1];

/// ------------------------------------------------------------
/// CHAT LIST TILE TIME (RIGHT SIDE)
/// ------------------------------------------------------------
/// Today      → 4:00 PM
/// Yesterday  → Yesterday
/// Older      → dd/MM/yyyy
String chatListTimeLabel(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDay = DateTime(time.year, time.month, time.day);

  if (messageDay == today) {
    return DateFormat('h:mm a').format(time);
  }

  if (messageDay == yesterday) {
    return 'Yesterday';
  }

  return DateFormat('dd/MM/yyyy').format(time);
}

/// ------------------------------------------------------------
/// USER PRESENCE SUBTITLE (CHAT HEADER)
/// ------------------------------------------------------------
/// Telegram / WhatsApp style
/// Priority handled in UI:
/// typing…  >  online  >  last seen
String presenceSubtitle(UserPresence presence) {
  if (presence.online) return 'online';

  final lastSeen = presence.lastSeen;
  if (lastSeen == null) return '';

  final now = DateTime.now();
  final diff = now.difference(lastSeen);

  if (diff.inMinutes < 1) {
    return 'last seen just now';
  }

  if (diff.inMinutes < 60) {
    return 'last seen ${diff.inMinutes} min ago';
  }

  if (diff.inHours < 24) {
    return 'last seen today at ${DateFormat('h:mm a').format(lastSeen)}';
  }

  if (diff.inDays == 1) {
    return 'last seen yesterday at ${DateFormat('h:mm a').format(lastSeen)}';
  }

  return 'last seen ${DateFormat('dd MMM at h:mm a').format(lastSeen)}';
}
