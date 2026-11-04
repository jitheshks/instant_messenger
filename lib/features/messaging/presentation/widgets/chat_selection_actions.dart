import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';

/// Contextual AppBar action buttons builder for message multi-selection mode.
class ChatSelectionActions {
  static List<Widget> build({
    required BuildContext context,
    required WidgetRef ref,
    required ChatControllerArgs chatArgs,
    required ChatTimelineState timelineState,
    required Set<String> selectionState,
    required ChatScreenSelectionNotifier selectionNotifier,
    required void Function(ChatMessage msg) onSetReply,
    required void Function(List<ChatMessage> msgs) onOpenForwardSheet,
    required void Function(List<ChatMessage> msgs) onCopyMessages,
  }) {
    final selectedMsgs =
        timelineState.messages
            .where((m) => selectionState.contains(m.id))
            .toList()
          ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    final canCancelFailedUploads =
        selectedMsgs.isNotEmpty &&
        selectedMsgs.every(
          (m) =>
              m.type == MessageType.media &&
              m.failure == MessageFailureReason.uploadFailed,
        );

    return [
      IconButton(
        icon: const Icon(Icons.reply),
        tooltip: 'Reply',
        onPressed: () {
          final targetId = selectionState.last;
          final msg = timelineState.messages.firstWhere(
            (m) => m.id == targetId,
            orElse: () => selectedMsgs.isNotEmpty
                ? selectedMsgs.last
                : ChatMessage(
                    id: targetId,
                    chatId: chatArgs.chatId,
                    senderId: '',
                    text: '',
                    sentAt: DateTime.now().toUtc(),
                    deliveryState: DeliveryState.sent,
                    type: MessageType.text,
                  ),
          );
          onSetReply(msg);
          selectionNotifier.clear();
        },
      ),
      IconButton(
        icon: const Icon(Icons.forward),
        tooltip: 'Forward',
        onPressed: () {
          if (selectedMsgs.isEmpty) return;
          onOpenForwardSheet(selectedMsgs);
        },
      ),
      if (selectedMsgs.any((m) => m.text.trim().isNotEmpty))
        IconButton(
          icon: const Icon(Icons.content_copy),
          tooltip: 'Copy',
          onPressed: () => onCopyMessages(selectedMsgs),
        ),
      if (canCancelFailedUploads)
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Cancel upload',
          onPressed: () {
            for (final m in selectedMsgs) {
              ref
                  .read(chatSendNotifierProvider(chatArgs).notifier)
                  .cancelMediaMessage(m.id);
            }
            selectionNotifier.clear();
          },
        ),
    ];
  }
}
