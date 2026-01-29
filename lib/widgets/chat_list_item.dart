import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_summary.dart';
import '../controller/chats_tab_selection_controller.dart';
import '../utils/chat_date.dart';
import '../utils/chat_route.dart';
import 'header_tile.dart';

class ChatListItem extends StatelessWidget {
  final ChatSummary chat;
  final String displayName; 

  const ChatListItem({
    super.key,
    required this.chat,
    required this.displayName, required Null Function() onTap,
  });

  String _deriveOtherUserId() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (chat.members.length == 2) {
      return chat.members.firstWhere(
        (m) => m != currentUid,
        orElse: () => '',
      );
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final isSelected = context.select<ChatsTabSelectionController, bool>(
      (sel) => sel.isSelected(chat.id),
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
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      onTap: () {
        final selection = context.read<ChatsTabSelectionController>();

        if (selection.active) {
          selection.toggle(chat.id);
          return;
        }

        final otherUserId = chat.otherUserId.isNotEmpty
            ? chat.otherUserId
            : _deriveOtherUserId();

        if (otherUserId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot open chat')),
          );
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
      onLongPress: () =>
          context.read<ChatsTabSelectionController>().toggle(chat.id),
      useListTile: true,
    );
  }
}
