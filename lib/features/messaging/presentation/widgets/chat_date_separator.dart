import 'package:flutter/material.dart';
import 'package:instant_messenger/shared/utils/chat_date.dart';

/// Reusable chat timeline date badge separator pill.
class ChatDateSeparator extends StatelessWidget {
  final DateTime date;
  final DateTime? now;

  const ChatDateSeparator({
    super.key,
    required this.date,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveNow = now ?? DateTime.now();
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          chatDateLabel(date, effectiveNow),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
