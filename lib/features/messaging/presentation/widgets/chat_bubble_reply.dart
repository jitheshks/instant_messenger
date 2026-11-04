import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// WhatsApp-style quote card rendered inside a ChatBubble when a message
/// is replying to another message.
class ChatBubbleReply extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final double maxWidth;
  final Color textColor;
  final void Function(String messageId)? onTapQuote;

  const ChatBubbleReply({
    super.key,
    required this.msg,
    required this.isMe,
    required this.maxWidth,
    required this.textColor,
    this.onTapQuote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final accentBarColor = isMe
        ? (isDark ? AppColors.brandAccent : AppColors.brandPrimary)
        : cs.primary;
    final replyBgColor = isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.06);

    String quoteText = (msg.replyText ?? '').trim();
    if (quoteText.isEmpty && msg.replyMediaKind != null) {
      quoteText = switch (msg.replyMediaKind!) {
        'image' => '📷 Photo',
        'video' => '🎥 Video',
        'audio' => '🎵 Audio',
        'document' => '📄 Document',
        _ => '[${msg.replyMediaKind}]',
      };
    }

    final replyWidget = Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(minWidth: 80, maxWidth: maxWidth - 20),
      decoration: BoxDecoration(
        color: replyBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accentBarColor, width: 3.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            msg.replySenderName ?? 'Reply',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accentBarColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            quoteText,
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.85),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTapQuote != null && msg.replyToMessageId != null) {
      return GestureDetector(
        onTap: () => onTapQuote!(msg.replyToMessageId!),
        child: replyWidget,
      );
    }

    return replyWidget;
  }
}
