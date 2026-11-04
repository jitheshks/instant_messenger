// lib/features/messaging/presentation/widgets/chat_app_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/domain/models/user_presence.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_app_bar_actions.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_presence_subtitle.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_selection_actions.dart';
import 'package:instant_messenger/shared/widgets/bars/app_bar_header.dart';

/// Clean AppBar component for the chat conversation screen.
///
/// Automatically toggles between standard conversation header with presence/call actions
/// and contextual multi-selection mode with reply/forward/copy/delete actions.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final WidgetRef ref;
  final ChatControllerArgs chatArgs;
  final String contactName;
  final String contactAvatar;
  final bool isGroup;
  final bool isTimelineReady;
  final bool isTyping;
  final AsyncValue<UserPresence> presenceAsync;
  final ChatTimelineState timelineState;
  final Set<String> selectionState;
  final ChatScreenSelectionNotifier selectionNotifier;
  final void Function(ChatMessage message) onSetReply;
  final void Function(List<ChatMessage> messages) onOpenForwardSheet;
  final void Function(List<ChatMessage> messages) onCopyMessages;

  const ChatAppBar({
    super.key,
    required this.ref,
    required this.chatArgs,
    required this.contactName,
    required this.contactAvatar,
    required this.isGroup,
    required this.isTimelineReady,
    required this.isTyping,
    required this.presenceAsync,
    required this.timelineState,
    required this.selectionState,
    required this.selectionNotifier,
    required this.onSetReply,
    required this.onOpenForwardSheet,
    required this.onCopyMessages,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectionState.isNotEmpty;

    final String resolvedTitle;
    if (!isGroup && chatArgs.otherUserId.isNotEmpty) {
      final contacts = ref.watch(contactsDataControllerProvider);
      resolvedTitle = ContactIdentityResolver.resolveIdentity(
        phoneE164: null,
        userId: chatArgs.otherUserId,
        contacts: contacts.cachedMatched,
        fallback: contactName,
      );
    } else {
      resolvedTitle = contactName;
    }

    return AppBar(
      leading: hasSelection
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: selectionNotifier.clear,
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/chats');
                }
              },
            ),
      titleSpacing: 0,
      title: hasSelection
          ? Text(
              '${selectionState.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          : AppBarHeader(
              title: resolvedTitle,
              avatarUrl: contactAvatar.isEmpty ? null : contactAvatar,
              radius: 16,
              onTap: () {
                if (isGroup) {
                  context.push(
                    '/group-profile/${chatArgs.chatId}',
                    extra: {
                      'chatId': chatArgs.chatId,
                      'title': resolvedTitle,
                      'avatarUrl': contactAvatar,
                    },
                  );
                } else {
                  context.push(
                    '/contact-profile/${chatArgs.chatId}',
                    extra: {
                      'chatId': chatArgs.chatId,
                      'peerUserId': chatArgs.otherUserId,
                      'peerName': resolvedTitle,
                      'avatarUrl': contactAvatar,
                    },
                  );
                }
              },
              subtitle: (!isTimelineReady || isGroup)
                  ? const SizedBox.shrink()
                  : ChatPresenceSubtitle(
                      isTyping: isTyping,
                      presenceAsync: presenceAsync,
                    ),
            ),
      actions: hasSelection
          ? ChatSelectionActions.build(
              context: context,
              ref: ref,
              chatArgs: chatArgs,
              timelineState: timelineState,
              selectionState: selectionState,
              selectionNotifier: selectionNotifier,
              onSetReply: onSetReply,
              onOpenForwardSheet: onOpenForwardSheet,
              onCopyMessages: onCopyMessages,
            )
          : ChatAppBarActions.build(
              context,
              ref: ref,
              chatId: chatArgs.chatId,
              peerUserId: isGroup ? null : chatArgs.otherUserId,
              peerName: resolvedTitle,
            ),
    );
  }
}
