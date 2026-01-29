import 'package:flutter/material.dart';
import 'package:instant_messenger/models/chat_message.dart';

class ChatDeliveryRow extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback? onRetry;

  const ChatDeliveryRow({
    super.key,
    required this.msg,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _hhmm(msg.sentAt),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(width: 2),
        _buildTick(),
      ],
    );
  }

  Widget _buildTick() {
    if (msg.hasFailed) {
      return GestureDetector(
        onTap: onRetry,
        child: const Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: Colors.redAccent,
        ),
      );
    }

    switch (msg.deliveryState) {
      case DeliveryState.read:
        return const Icon(Icons.done_all,
            size: 17, color: Colors.blueAccent);
      case DeliveryState.delivered:
        return const Icon(Icons.done_all,
            size: 17, color: Colors.grey);
      case DeliveryState.sent:
        return const Icon(Icons.done,
            size: 17, color: Colors.grey);
      case DeliveryState.sending:
        return const Icon(Icons.access_time,
            size: 15, color: Colors.grey);
    }
  }

  String _hhmm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? "PM" : "AM";
    return "$h:$mm $ampm";
  }
}
