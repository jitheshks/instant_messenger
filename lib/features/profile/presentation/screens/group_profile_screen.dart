import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/group_profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/group_members_tab.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/group_profile_header.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/group_settings_tab.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_action_buttons.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_media_section.dart';

/// Screen displaying group profile information, admin membership management,
/// shared group media, and group settings organized in three tabs.
class GroupProfileScreen extends ConsumerWidget {
  final String chatId;
  final String groupTitle;
  final String avatarUrl;

  const GroupProfileScreen({
    super.key,
    required this.chatId,
    required this.groupTitle,
    this.avatarUrl = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId =
        ref.watch(currentUserIdProvider) ?? SupabaseConfig.currentUserId ?? '';
    final args = GroupProfileArgs(
      chatId: chatId,
      currentUserId: currentUserId,
      initialTitle: groupTitle,
      initialAvatar: avatarUrl,
    );

    final state = ref.watch(groupProfileControllerProvider(args));
    final notifier = ref.read(groupProfileControllerProvider(args).notifier);

    final details = state.details;
    final title = details?.title ?? groupTitle;
    final avatar = details?.avatarUrl ?? avatarUrl;
    final description = details?.description;
    final memberCount = details?.memberCount ?? 0;
    final isAdmin = details?.isCurrentUserAdmin ?? false;
    final isMuted = details?.isMuted ?? false;
    final mediaSummary = details?.mediaSummary;

    return DefaultTabController(
      length: 3,
      initialIndex: state.selectedTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Group info'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'share') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sharing invite link for $title')),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Share group'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // 1. Group Header
                    GroupProfileHeader(
                      title: title,
                      avatarUrl: avatar,
                      description: description,
                      memberCount: memberCount,
                      isAdmin: isAdmin,
                      onEditTitle: (newTitle) async {
                        final ok = await notifier.updateTitle(newTitle);
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Group name updated')),
                          );
                        }
                      },
                      onEditAvatar: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Edit avatar feature')),
                        );
                      },
                    ),

                    // 2. Quick Actions
                    ProfileActionButtons(
                      actions: [
                        ProfileActionButtonItem(
                          icon: Icons.call_outlined,
                          label: 'Audio',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Group calling is coming soon.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        if (isAdmin)
                          ProfileActionButtonItem(
                            icon: Icons.person_add_outlined,
                            label: 'Add',
                            onTap: () => _openAddMemberSheet(context, notifier),
                          ),
                        ProfileActionButtonItem(
                          icon: Icons.search,
                          label: 'Search',
                          onTap: () {
                            context.pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    onTap: notifier.setTab,
                    tabs: [
                      Tab(text: 'Members ($memberCount)'),
                      Tab(text: 'Media (${mediaSummary?.totalCount ?? 0})'),
                      const Tab(text: 'Settings'),
                    ],
                  ),
                  Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              // Tab 1: Members
              GroupMembersTab(
                members: state.filteredMembers,
                isCurrentUserAdmin: isAdmin,
                onSearchChanged: notifier.setMemberSearch,
                onAddMember: isAdmin ? () => _openAddMemberSheet(context, notifier) : null,
                onToggleRole: (userId, newRole) async {
                  final ok = await notifier.setMemberRole(userId, newRole);
                  if (!context.mounted) return;
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Role updated to $newRole')),
                    );
                  } else {
                    final err = ref.read(groupProfileControllerProvider(args)).errorMessage;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err ?? 'Could not update role.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onRemoveMember: (userId, name) async {
                  final ok = await notifier.removeMember(userId);
                  if (!context.mounted) return;
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$name removed from group')),
                    );
                  } else {
                    final err = ref.read(groupProfileControllerProvider(args)).errorMessage;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err ?? 'Could not remove member.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),

              // Tab 2: Media
              mediaSummary != null
                  ? ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        ProfileMediaSection(mediaSummary: mediaSummary),
                      ],
                    )
                  : const Center(child: Text('No media shared')),

              // Tab 3: Settings
              GroupSettingsTab(
                isMuted: isMuted,
                isCurrentUserAdmin: isAdmin,
                onMuteChanged: notifier.toggleMute,
                onClearChat: () async {
                  await notifier.clearChat();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Group chat cleared locally')),
                    );
                  }
                },
                onExitGroup: () async {
                  final ok = await notifier.leaveGroup();
                  if (!context.mounted) return;
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Left group')),
                    );
                    context.go('/chats');
                  } else {
                    final err = ref.read(groupProfileControllerProvider(args)).errorMessage;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err ?? 'Could not leave group.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onReportGroup: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This feature is not available yet.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddMemberSheet(BuildContext context, GroupProfileNotifier notifier) {
    context.push('/contacts');
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
