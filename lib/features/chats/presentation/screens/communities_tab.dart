// lib/features/chats/presentation/screens/communities_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/shared/utils/chat_route.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Real application groups/communities tab backed by Supabase `public.chats` (type: group).
class CommunitiesTab extends ConsumerWidget {
  const CommunitiesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communitiesTabControllerProvider);
    final cs = Theme.of(context).colorScheme;

    Widget body;

    if (state.isLoading && state.groups.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.errorMessage != null && state.groups.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref
                    .read(communitiesTabControllerProvider.notifier)
                    .refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (state.groups.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'No groups yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Groups you belong to will appear here',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    } else {
      final currentUid = SupabaseConfig.currentUserId ?? '';

      body = RefreshIndicator(
        onRefresh: () =>
            ref.read(communitiesTabControllerProvider.notifier).refresh(),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: state.groups.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final group = state.groups[index];
            final groupTitle = (group.title != null && group.title!.isNotEmpty)
                ? group.title!
                : 'Group';

            return ListTile(
              leading: SafeAvatar(
                radius: 24,
                avatarUrl: group.avatarUrl,
                fallbackIcon: Icons.groups,
                fallbackName: groupTitle,
              ),
              title: Text(
                groupTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                group.lastMessage.isNotEmpty
                    ? group.lastMessage
                    : '${group.members.length} members',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(group.lastTime),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  if (group.unread > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${group.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                openChat(
                  context,
                  chatId: group.id,
                  currentUserId: currentUid,
                  isGroup: true,
                  contactName: groupTitle,
                  contactAvatar: group.avatarUrl ?? '',
                );
              },
            );
          },
        ),
      );
    }

    if (Scaffold.maybeOf(context) != null) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      body: body,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final isYesterday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day - 1;

    if (isToday) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      final period = local.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } else if (isYesterday) {
      return 'Yesterday';
    } else {
      return '${local.month}/${local.day}/${local.year}';
    }
  }
}
