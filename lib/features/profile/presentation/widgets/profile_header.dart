import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Reusable profile header displaying avatar, resolved identity, phone number, and status.
class ProfileHeader extends StatelessWidget {
  final String displayName;
  final String? phoneE164;
  final String? avatarUrl;
  final String? about;
  final VoidCallback? onAvatarTap;

  const ProfileHeader({
    super.key,
    required this.displayName,
    this.phoneE164,
    this.avatarUrl,
    this.about,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final formattedPhone = phoneE164 != null && phoneE164!.isNotEmpty
        ? phoneE164!.trim()
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // Large profile avatar
        GestureDetector(
          onTap: onAvatarTap,
          child: SafeAvatar(
            radius: 54,
            avatarUrl: avatarUrl,
            fallbackName: displayName,
            fallbackIcon: Icons.person,
          ),
        ),
        const SizedBox(height: 16),

        // Display name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Phone number
        if (formattedPhone != null && formattedPhone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            formattedPhone,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: secondaryTextColor,
              letterSpacing: 0.2,
            ),
          ),
        ],

        // About / Bio status
        if (about != null && about!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              about!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: secondaryTextColor,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
