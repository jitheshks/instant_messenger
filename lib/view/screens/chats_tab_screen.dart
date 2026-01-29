import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/widgets/chat_list_item.dart';
import 'package:provider/provider.dart';

import 'package:instant_messenger/widgets/tab_menu.dart';
import 'package:instant_messenger/widgets/searchable_selectable_app_bar.dart';
import 'package:instant_messenger/widgets/delete_chats_dialog.dart';

import 'package:instant_messenger/controller/chats_tab_controller.dart';
import 'package:instant_messenger/controller/chats_tab_selection_controller.dart';
import 'package:instant_messenger/controller/search_bar_controller.dart';
import 'package:instant_messenger/models/chat_summary.dart';
import 'package:instant_messenger/controller/contacts_data_controller.dart';

class ChatsTabScreen extends StatelessWidget {
  const ChatsTabScreen({super.key});


  

  String resolveDisplayName(BuildContext context, ChatSummary chat) {
    final contacts = context.watch<ContactsDataController?>();

    // Contacts not ready → show phone
    if (contacts == null || contacts.cachedMatched.isEmpty) {
      return chat.otherPhoneE164 ?? chat.otherUserId;
    }

    // Match by phone number
    for (final entry in contacts.cachedMatched) {
      if (entry.phoneE164 == chat.otherPhoneE164) {
        return entry.displayName;
      }
    }

    // Fallback → phone
    return chat.otherPhoneE164 ?? chat.otherUserId;
  }

  String deriveOtherUserId(ChatSummary chat) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (chat.members.length == 2) {
      return chat.members.firstWhere((m) => m != currentUid, orElse: () => '');
    }
    return '';
  }


  @override
  Widget build(BuildContext context) {

    WidgetsBinding.instance.addPostFrameCallback((_) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isNotEmpty) {
    context.read<ChatsTabController>().ensureBound(uid);
  }
});
    debugPrint('🟢 BUILD → ChatsTabScreen');
    final chatsController = context.watch<ChatsTabController?>();

    if (chatsController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

//    if (uid.isNotEmpty) {
//   chatsController.ensureBound(uid);
// }

    final selection = context.watch<ChatsTabSelectionController>();
    final idsNotifier = ValueNotifier<List<String>>(<String>[]);

    return ChangeNotifierProvider<SearchBarController>(
      create: (_) => SearchBarController(),
      child: Scaffold(
        appBar: SearchableSelectableAppBar(
          title: 'Chats',
          searchHint: 'Search chats',
          normalActions: (_) => const [TabMenu(kind: TabKind.chats)],
          selectionMode: selection.active,
          selectedCount: selection.count,
          onCloseSelection: () => selection.clear(),
          onSelectAll: () => context
              .read<ChatsTabSelectionController>()
              .selectAll(idsNotifier.value),
          selectionActions: () => [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ids = selection.selected.toList();
                final controller = context.read<ChatsTabController>();

                final confirm = await showDeleteChatDialog(context, ids.length);
                if (confirm != null) {
                  await controller.deleteSelectedChats(ids);

                  if (!context.mounted) return;
                  selection.clear();
                }
              },
            ),
          ],
        ),
      body: Builder(
  builder: (context) {
    // 1️⃣ Still loading local (Hive) data → spinner
    if (!chatsController.isReady) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 2️⃣ Loaded, but confirmed empty → empty state
    if (chatsController.chats.isEmpty) {
      return EmptyChatsView(
        onStartChat: () => GoRouter.of(context).push('/contacts'),
      );
    }

    // 3️⃣ Loaded + has chats → list
    return AnimatedList(
      key: chatsController.listKey,
      initialItemCount: chatsController.chats.length,
      itemBuilder: (context, index, animation) {
        final chat = chatsController.chats[index];
        final displayName = resolveDisplayName(context, chat);
        final otherUserId = deriveOtherUserId(chat);

        return SizeTransition(
          sizeFactor: animation,
          child: ChatListItem(
            key: ValueKey(chat.id),
            chat: chat,
            displayName: displayName,
            onTap: () {
              if (otherUserId.isEmpty) {
                debugPrint(
                  '❌ Missing otherUserId for chat=${chat.id}',
                );
                return;
              }

              context.push(
                '/chats/chat/${chat.id}',
                extra: {
                  'currentUserId': uid,
                  'otherUserId': otherUserId,
                  'contactName': displayName,
                  'contactAvatar': '',
                },
              );
            },
          ),
        );
      },
    );
  },
),


        floatingActionButton: selection.active
            ? null
            : FloatingActionButton(
                backgroundColor: const Color(0xFF25D366),
                child: const Icon(Icons.chat),
                onPressed: () => GoRouter.of(context).push('/contacts'),
              ),
      ),
    );
  }
}

class EmptyChatsView extends StatelessWidget {
  final VoidCallback onStartChat;

  const EmptyChatsView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('No chats yet'),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onStartChat,
          child: const Text('Start a chat'),
        ),
      ],
    );
  }
}
