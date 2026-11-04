import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// WhatsApp-style preview banner positioned above the composer input pill
/// when replying to a message.
class ReplyComposerPreview extends StatelessWidget {
  final ChatMessage replyTarget;
  final String senderName;
  final VoidCallback onCancel;

  const ReplyComposerPreview({
    super.key,
    required this.replyTarget,
    required this.senderName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatTheme = ChatThemeExtension.of(context);

    String previewText = replyTarget.text.trim();
    if (previewText.isEmpty && replyTarget.media != null) {
      previewText = switch (replyTarget.media!.kind) {
        MediaKind.image => '📷 Photo',
        MediaKind.video => '🎥 Video',
        MediaKind.audio => '🎵 Audio',
        MediaKind.document => '📄 Document',
      };
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
      decoration: BoxDecoration(
        color: chatTheme.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: cs.onSurfaceVariant,
            splashRadius: 18,
            onPressed: onCancel,
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}
