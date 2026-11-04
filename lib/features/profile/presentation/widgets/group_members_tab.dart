import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/features/profile/domain/models/group_profile_details.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Members tab in Group Profile displaying search, member count, admin badges, and role actions.
class GroupMembersTab extends StatelessWidget {
  final List<GroupMemberDetails> members;
  final bool isCurrentUserAdmin;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onAddMember;
  final void Function(String userId, String currentRole)? onToggleRole;
  final void Function(String userId, String name)? onRemoveMember;

  const GroupMembersTab({
    super.key,
    required this.members,
    required this.isCurrentUserAdmin,
    required this.onSearchChanged,
    this.onAddMember,
    this.onToggleRole,
    this.onRemoveMember,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Member search bar
        TextField(
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search members',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceContainer
                : AppColors.lightSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // "Add members" tile (for admins)
        if (isCurrentUserAdmin && onAddMember != null) ...[
          ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.15),
              child: const Icon(
                Icons.person_add,
                size: 20,
                color: AppColors.brandPrimary,
              ),
            ),
            title: const Text(
              'Add members',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.brandPrimary,
              ),
            ),
            onTap: onAddMember,
          ),
          Divider(height: 1, indent: 56, color: theme.dividerColor),
        ],

        // Member list
        ...members.map((member) {
          final formattedPhone = member.phoneE164 != null && member.phoneE164!.isNotEmpty
              ? member.phoneE164!.trim()
              : null;

          return ListTile(
            leading: SafeAvatar(
              radius: 20,
              avatarUrl: member.avatarUrl,
              fallbackName: member.displayName,
              fallbackIcon: Icons.person,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    member.isCurrentUser ? 'You' : member.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (member.isAdmin) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Group Admin',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              formattedPhone ?? member.about ?? (member.isCurrentUser ? 'Hey there! I am using Instant Messenger' : ''),
              style: TextStyle(fontSize: 13, color: secondaryTextColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: (isCurrentUserAdmin && !member.isCurrentUser)
                ? () => _showMemberOptions(context, member)
                : null,
          );
        }),
      ],
    );
  }

  void _showMemberOptions(BuildContext context, GroupMemberDetails member) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SafeAvatar(
                radius: 18,
                avatarUrl: member.avatarUrl,
                fallbackName: member.displayName,
              ),
              title: Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(member.isAdmin ? 'Group Admin' : 'Member'),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                member.isAdmin ? Icons.shield_outlined : Icons.security,
                color: AppColors.brandPrimary,
              ),
              title: Text(member.isAdmin ? 'Dismiss as admin' : 'Make group admin'),
              onTap: () {
                Navigator.of(ctx).pop();
                if (onToggleRole != null) {
                  final newRole = member.isAdmin ? 'member' : 'admin';
                  onToggleRole!(member.userId, newRole);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: AppColors.error),
              title: Text(
                'Remove ${member.displayName}',
                style: const TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                if (onRemoveMember != null) {
                  onRemoveMember!(member.userId, member.displayName);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
