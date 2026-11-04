import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';

import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/shared/utils/chat_date.dart';
import 'package:instant_messenger/shared/utils/chat_route.dart';
import 'package:instant_messenger/shared/widgets/tiles/header_tile.dart';

class ChatListItem extends ConsumerWidget {
  final ChatSummary chat;
  final String displayName;
  final VoidCallback? onTap;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.displayName,
    this.onTap,
  });

  String _deriveOtherUserId() {
    final currentUid = SupabaseConfig.currentUserId ?? '';
    if (chat.members.length == 2) {
      return chat.members.firstWhere((m) => m != currentUid, orElse: () => '');
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = SupabaseConfig.currentUserId ?? '';

    final isSelected = ref.watch(
      chatsTabSelectionControllerProvider.select(
        (set) => set.contains(chat.id),
      ),
    );

    final timeStr = chatListTimeLabel(chat.lastTime);

    return HeaderTile(
      key: ValueKey(chat.id),
      displayName: displayName, // ✅ DIRECT USE
      bio: chat.lastMessage,
      avatarUrl: chat.avatarUrl,
      radius: 24,
      selected: isSelected,
      unreadCount: chat.unread,
      isLastMessageMine: chat.lastSenderId == uid,
      lastMessageStatus: chat.lastMessageStatus,
      muted: chat.muted,
      trailing: Text(
        timeStr,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () {
        final selection = ref.read(chatsTabSelectionControllerProvider);

        if (selection.isNotEmpty) {
          ref
              .read(chatsTabSelectionControllerProvider.notifier)
              .toggle(chat.id);
          return;
        }

        if (onTap != null) {
          onTap!();
          return;
        }

        final otherUserId = chat.otherUserId.isNotEmpty
            ? chat.otherUserId
            : _deriveOtherUserId();

        if (otherUserId.isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Cannot open chat')));
          return;
        }
        openChat(
          context,
          chatId: chat.id,
          currentUserId: uid,
          otherUserId: otherUserId, // 🔥 THIS WAS MISSING
          contactName: displayName,
          contactAvatar: chat.avatarUrl ?? '',
        );
      },
      onLongPress: () => ref
          .read(chatsTabSelectionControllerProvider.notifier)
          .toggle(chat.id),
      useListTile: true,
    );
  }
}
