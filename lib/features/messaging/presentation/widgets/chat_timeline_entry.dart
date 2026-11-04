// lib/features/messaging/presentation/widgets/chat_timeline_entry.dart

import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/shared/utils/chat_date.dart';

/// Lightweight data model representing an entry in a virtualized chat timeline.
sealed class TimelineEntry {
  final String id;
  final DateTime time;

  const TimelineEntry({required this.id, required this.time});
}

/// Represents an individual chat message in the timeline.
class MessageTimelineEntry extends TimelineEntry {
  final ChatMessage message;

  MessageTimelineEntry(this.message)
      : super(id: 'msg_${message.id}', time: message.sentAt);
}

/// Represents an audio/video call log event in the timeline.
class CallTimelineEntry extends TimelineEntry {
  final CallRecord call;

  CallTimelineEntry(this.call)
      : super(id: 'call_${call.id}', time: call.startedAt);
}

/// Represents a date separator dividing messages from different days.
class DateSeparatorTimelineEntry extends TimelineEntry {
  final DateTime date;

  DateSeparatorTimelineEntry(this.date)
      : super(id: 'sep_${dayKey(date)}', time: date);
}

/// Represents a loading spinner placed at the top of the reversed list during pagination.
class LoadingMoreTimelineEntry extends TimelineEntry {
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  LoadingMoreTimelineEntry()
      : super(
          id: 'loading_more_indicator',
          time: _epoch,
        );
}

/// Pure helper function that compiles raw messages and calls into an ordered,
/// reversed list of [TimelineEntry] objects ready for virtualized [ListView.builder].
///
/// Order:
/// - Index 0: Newest timeline item (bottom of reverse ListView)
/// - Index `length - 1`: Oldest timeline item or loading spinner (top of reverse ListView)
List<TimelineEntry> buildTimelineEntries({
  required List<ChatMessage> messages,
  required List<CallRecord> calls,
  required bool loadingMore,
  DateTime? now,
}) {
  if (messages.isEmpty && calls.isEmpty) {
    return const [];
  }

  // 1. Combine into chronological sortable pairs
  final sortedItems = <_SortableEntry>[
    ...messages.map((m) => _SortableEntry(m.sentAt, m)),
    ...calls.map((c) => _SortableEntry(c.startedAt, c)),
  ];

  sortedItems.sort((a, b) => a.time.compareTo(b.time));

  // 2. Insert date separators between distinct calendar days
  final chronologicalEntries = <TimelineEntry>[];
  String? lastDayKey;

  for (final item in sortedItems) {
    final key = dayKey(item.time);
    if (lastDayKey != key) {
      chronologicalEntries.add(DateSeparatorTimelineEntry(item.time));
      lastDayKey = key;
    }

    final obj = item.object;
    if (obj is ChatMessage) {
      chronologicalEntries.add(MessageTimelineEntry(obj));
    } else if (obj is CallRecord) {
      chronologicalEntries.add(CallTimelineEntry(obj));
    }
  }

  // 3. In reverse ListView, index 0 is at the bottom (newest).
  // Reversing chronological entries ensures index 0 is newest.
  final reversed = chronologicalEntries.reversed.toList();

  // 4. Loading spinner belongs at the top (oldest boundary), which is the end of the reversed list
  if (loadingMore) {
    reversed.add(LoadingMoreTimelineEntry());
  }

  return reversed;
}

class _SortableEntry {
  final DateTime time;
  final Object object;

  const _SortableEntry(this.time, this.object);
}
