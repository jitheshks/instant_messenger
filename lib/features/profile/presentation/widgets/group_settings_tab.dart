import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';

/// Settings tab for Group Profile displaying group preferences, mute toggles,
/// clear chat, and exit group actions.
class GroupSettingsTab extends StatelessWidget {
  final bool isMuted;
  final bool isCurrentUserAdmin;
  final ValueChanged<bool> onMuteChanged;
  final VoidCallback onClearChat;
  final VoidCallback onExitGroup;
  final VoidCallback onReportGroup;

  const GroupSettingsTab({
    super.key,
    required this.isMuted,
    required this.isCurrentUserAdmin,
    required this.onMuteChanged,
    required this.onClearChat,
    required this.onExitGroup,
    required this.onReportGroup,
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
        // 1. Mute notifications
        SwitchListTile.adaptive(
          title: Text(
            'Mute notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: primaryTextColor,
            ),
          ),
          subtitle: Text(
            isMuted ? 'Muted' : 'Off',
            style: TextStyle(fontSize: 13, color: secondaryTextColor),
          ),
          secondary: const Icon(Icons.notifications_off_outlined),
          value: isMuted,
          activeTrackColor: AppColors.brandPrimary,
          onChanged: onMuteChanged,
        ),
        Divider(height: 1, indent: 56, color: theme.dividerColor),

        // 2. Group permissions
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(
            'Group permissions',
            style: TextStyle(fontSize: 16, color: primaryTextColor),
          ),
          subtitle: Text(
            isCurrentUserAdmin
                ? 'Edit group info, send messages'
                : 'Only admins can edit group settings',
            style: TextStyle(fontSize: 13, color: secondaryTextColor),
          ),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Group permissions configured to default.'),
              ),
            );
          },
        ),
        Divider(height: 1, indent: 56, color: theme.dividerColor),

        // 3. Clear chat
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
          title: const Text(
            'Clear chat',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Delete messages from your device only'),
          onTap: () => _confirmClearChat(context),
        ),
        Divider(height: 1, indent: 56, color: theme.dividerColor),

        // 4. Exit group
        ListTile(
          leading: const Icon(Icons.exit_to_app, color: AppColors.error),
          title: const Text(
            'Exit group',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
          ),
          onTap: () => _confirmExitGroup(context),
        ),
        Divider(height: 1, indent: 56, color: theme.dividerColor),

        // 5. Report group
        ListTile(
          leading: const Icon(Icons.thumb_down_outlined, color: AppColors.error),
          title: const Text(
            'Report group',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
          ),
          onTap: () => _confirmReportGroup(context),
        ),
      ],
    );
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this group chat?'),
        content: const Text(
          'Messages will only be cleared from this device and other participants will keep their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onClearChat();
            },
            child: const Text('Clear chat', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _confirmExitGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit group?'),
        content: const Text(
          'You will no longer receive messages or calls from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onExitGroup();
            },
            child: const Text('Exit', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _confirmReportGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report group?'),
        content: const Text('This feature is not available yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
