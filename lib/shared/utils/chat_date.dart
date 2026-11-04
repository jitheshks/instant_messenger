import 'package:intl/intl.dart';

/// ------------------------------------------------------------
/// CHAT DATE HELPERS
/// ------------------------------------------------------------

/// Returns a human-friendly label for chat message grouping
/// Examples:
/// Today, Yesterday, Monday, 12 Jan 2025
String chatDateLabel(DateTime date, DateTime now) {
  final localDate = date.toLocal();
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final d = DateTime(localDate.year, localDate.month, localDate.day);
  final diff = today.difference(d).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff <= 6) return _weekdayName(d.weekday);

  return '${localDate.day} ${_monthName(localDate.month)} ${localDate.year}';
}

/// Stable key for grouping messages by day
/// Format: YYYY-MM-DD
String dayKey(DateTime dt) {
  final local = dt.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd';
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
  final localTime = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDay = DateTime(localTime.year, localTime.month, localTime.day);

  if (messageDay == today) {
    return DateFormat('h:mm a').format(localTime);
  }

  if (messageDay == yesterday) {
    return 'Yesterday';
  }

  return DateFormat('dd/MM/yyyy').format(localTime);
}

/// ------------------------------------------------------------
/// USER PRESENCE SUBTITLE (CHAT HEADER)
/// ------------------------------------------------------------
/// Telegram / WhatsApp style
/// Priority handled in UI:
/// typing…  >  online  >  last seen
String formatPresenceSubtitle({required bool online, DateTime? lastSeen}) {
  if (online) return 'online';

  if (lastSeen == null) return '';

  final localLastSeen = lastSeen.toLocal();
  final now = DateTime.now();
  final diff = now.difference(localLastSeen);

  if (diff.inMinutes < 1) {
    return 'last seen just now';
  }

  if (diff.inMinutes < 60) {
    return 'last seen ${diff.inMinutes} min ago';
  }

  if (diff.inHours < 24) {
    return 'last seen today at ${DateFormat('h:mm a').format(localLastSeen)}';
  }

  if (diff.inDays == 1) {
    return 'last seen yesterday at ${DateFormat('h:mm a').format(localLastSeen)}';
  }

  return 'last seen ${DateFormat('dd MMM at h:mm a').format(localLastSeen)}';
}
