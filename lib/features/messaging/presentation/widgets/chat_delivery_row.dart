import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

class ChatDeliveryRow extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final VoidCallback? onRetry;

  const ChatDeliveryRow({
    super.key,
    required this.msg,
    this.isMe = true,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final chatTheme = ChatThemeExtension.of(context);
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _hhmm(msg.sentAt),
          style: TextStyle(
            fontSize: 11,
            color: isMe ? chatTheme.timestampSent : chatTheme.timestampReceived,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 2),
          _buildTick(chatTheme, cs),
        ],
      ],
    );
  }

  Widget _buildTick(ChatThemeExtension chatTheme, ColorScheme cs) {
    if (msg.hasFailed) {
      return GestureDetector(
        onTap: onRetry,
        child: Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: cs.error,
        ),
      );
    }

    switch (msg.deliveryState) {
      case DeliveryState.read:
        return Icon(Icons.done_all, size: 17, color: chatTheme.tickRead);
      case DeliveryState.delivered:
        return Icon(Icons.done_all, size: 17, color: chatTheme.tickDelivered);
      case DeliveryState.sent:
        return Icon(Icons.done, size: 17, color: chatTheme.tickDelivered);
      case DeliveryState.sending:
        return Icon(Icons.access_time, size: 15, color: chatTheme.tickDelivered);
    }
  }

  String _hhmm(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? "PM" : "AM";
    return "$h:$mm $ampm";
  }
}
