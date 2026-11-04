import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';

/// Reusable settings card displaying notifications, encryption, and privacy toggles.
class ProfileSettingsCard extends StatelessWidget {
  final bool isMuted;
  final ValueChanged<bool> onMuteChanged;
  final String contactName;

  const ProfileSettingsCard({
    super.key,
    required this.isMuted,
    required this.onMuteChanged,
    required this.contactName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerColor = isDark
        ? AppColors.darkSurfaceContainer
        : AppColors.lightSurface;
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: containerColor,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
        child: Column(
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

            // 2. Custom notifications
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: Text(
                'Custom notifications',
                style: TextStyle(fontSize: 16, color: primaryTextColor),
              ),
              subtitle: Text(
                'Default tone, vibrate',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              onTap: () => _showComingSoon(context, 'Custom notifications'),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            // 3. Media visibility
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                'Media visibility',
                style: TextStyle(fontSize: 16, color: primaryTextColor),
              ),
              subtitle: Text(
                'Show newly downloaded media in gallery',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              onTap: () => _showComingSoon(context, 'Media visibility'),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            // 4. Honest Encryption Info
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(
                'Encryption',
                style: TextStyle(fontSize: 16, color: primaryTextColor),
              ),
              subtitle: Text(
                'Protected by Transport Layer Security & RLS',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              onTap: () => _showEncryptionInfo(context),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            // 5. Disappearing messages
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(
                'Disappearing messages',
                style: TextStyle(fontSize: 16, color: primaryTextColor),
              ),
              subtitle: Text(
                'Off (Coming soon)',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Beta', style: TextStyle(fontSize: 11)),
              ),
              onTap: () => _showComingSoon(context, 'Disappearing messages'),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            // 6. Chat lock
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(
                'Chat lock',
                style: TextStyle(fontSize: 16, color: primaryTextColor),
              ),
              subtitle: Text(
                'Lock and hide this chat on this device',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              onTap: () => _showComingSoon(context, 'Chat lock'),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(feature),
        content: Text('$feature will be enabled in an upcoming release.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEncryptionInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('Security Details'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your messages and calls are transported using encrypted TLS connections and authorized strictly via Row-Level Security (RLS) on Supabase.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text(
              'Only confirmed participants in this conversation possess authorization to query these records. Client-to-client end-to-end signal encryption is currently planned for Phase 8.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Destructive actions section for clearing chat, blocking, and reporting contacts.
class ProfileDangerCard extends StatelessWidget {
  final String contactName;
  final VoidCallback onClearChat;
  final VoidCallback onBlock;
  final VoidCallback onReport;

  const ProfileDangerCard({
    super.key,
    required this.contactName,
    required this.onClearChat,
    required this.onBlock,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerColor = isDark
        ? AppColors.darkSurfaceContainer
        : AppColors.lightSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: containerColor,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
              title: const Text(
                'Clear chat',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Delete messages from your device'),
              onTap: () => _confirmClearChat(context),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            ListTile(
              leading: const Icon(Icons.block, color: AppColors.error),
              title: Text(
                'Block $contactName',
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
              onTap: () => _confirmBlock(context),
            ),
            Divider(height: 1, indent: 56, color: theme.dividerColor),

            ListTile(
              leading: const Icon(Icons.thumb_down_outlined, color: AppColors.error),
              title: Text(
                'Report $contactName',
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
              onTap: () => _confirmReport(context),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'Messages will only be cleared from this device and cannot be recovered.',
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

  void _confirmBlock(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $contactName?'),
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

  void _confirmReport(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Report $contactName?'),
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
