// lib/features/messaging/presentation/widgets/chat_bubble.dart

import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble_media.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble_reply.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_delivery_row.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/swipe_to_reply.dart';

/// Bubble widget presenting an individual chat message in the message timeline.
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final bool isSelected;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final void Function(String messageId)? onTapQuote;
  final VoidCallback? onSwipeReply;

  const ChatBubble({
    super.key,
    required this.msg,
    required this.isMe,
    this.isSelected = false,
    this.onRetry,
    this.onCancel,
    this.onTapQuote,
    this.onSwipeReply,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.72;
    final chatTheme = ChatThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = isMe ? chatTheme.bubbleSent : chatTheme.bubbleReceived;
    final textColor = isMe ? chatTheme.textSent : chatTheme.textReceived;

    final selectionInk = isSelected
        ? (isDark
              ? (isMe
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.15))
              : (isMe
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                    : Colors.grey.shade300.withValues(alpha: 0.30)))
        : Colors.transparent;

    final baseTextStyle =
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 16, height: 1.25);
    final textStyle = baseTextStyle.copyWith(color: textColor);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: [
          if (isSelected)
            Positioned.fill(child: Container(color: selectionInk)),
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: onSwipeReply != null
                    ? SwipeToReply(
                        isMe: isMe,
                        onSwipeReply: onSwipeReply!,
                        child: _buildAnimatedBubble(
                          context,
                          maxW,
                          bubbleColor,
                          radius,
                          textStyle,
                          textColor,
                        ),
                      )
                    : _buildAnimatedBubble(
                        context,
                        maxW,
                        bubbleColor,
                        radius,
                        textStyle,
                        textColor,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBubble(
    BuildContext context,
    double maxW,
    Color bubbleColor,
    BorderRadius radius,
    TextStyle textStyle,
    Color textColor,
  ) {
    Widget bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (msg.isForwarded) _buildForwardedLabel(context, textColor),
        if (msg.hasReply)
          ChatBubbleReply(
            msg: msg,
            isMe: isMe,
            maxWidth: maxW,
            textColor: textColor,
            onTapQuote: onTapQuote,
          ),
        if (msg.type == MessageType.call)
          _buildCallLayout(context, textStyle, maxW, textColor)
        else if (msg.type == MessageType.text)
          _buildTextLayout(textStyle, maxW)
        else
          ChatBubbleMedia(
            media: msg.media,
            isMe: isMe,
            maxWidth: maxW,
            textColor: textColor,
            uploadProgress: msg.uploadProgress,
            isUploadFailed: msg.failure == MessageFailureReason.uploadFailed,
            onRetry: onRetry,
            onCancel: onCancel,
            deliveryRow: ChatDeliveryRow(msg: msg, onRetry: onRetry),
          ),
      ],
    );

    Widget bubble = Container(
      margin: EdgeInsets.only(right: isMe ? 6 : 0, left: isMe ? 0 : 6),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
      child: bubbleContent,
    );

    if (msg.deliveryState == DeliveryState.sending) {
      bubble = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: bubble,
      );
    }

    return bubble;
  }

  Widget _buildForwardedLabel(BuildContext context, Color textColor) {
    final labelColor = textColor.withValues(alpha: 0.70);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forward, size: 13, color: labelColor),
          const SizedBox(width: 4),
          Text(
            'Forwarded',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLayout(
    BuildContext context,
    TextStyle textStyle,
    double maxW,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call, size: 20, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg.text.isNotEmpty ? msg.text : 'Call',
              style: textStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          ChatDeliveryRow(msg: msg, isMe: isMe, onRetry: onRetry),
        ],
      ),
    );
  }

  Widget _buildTextLayout(TextStyle textStyle, double maxW) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW - 80),
          child: Text(
            msg.text,
            style: textStyle,
            textAlign: isMe ? TextAlign.right : TextAlign.left,
          ),
        ),
        if (isMe) ChatDeliveryRow(msg: msg, onRetry: onRetry),
      ],
    );
  }
}
