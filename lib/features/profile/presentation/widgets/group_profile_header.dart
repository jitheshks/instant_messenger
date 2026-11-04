import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Group profile header with editable title and avatar for authorized group administrators.
class GroupProfileHeader extends StatelessWidget {
  final String title;
  final String? avatarUrl;
  final String? description;
  final int memberCount;
  final bool isAdmin;
  final ValueChanged<String>? onEditTitle;
  final VoidCallback? onEditAvatar;

  const GroupProfileHeader({
    super.key,
    required this.title,
    this.avatarUrl,
    this.description,
    required this.memberCount,
    this.isAdmin = false,
    this.onEditTitle,
    this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        // Group avatar with admin edit badge
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            SafeAvatar(
              radius: 54,
              avatarUrl: avatarUrl,
              fallbackName: title,
              fallbackIcon: Icons.groups,
            ),
            if (isAdmin && onEditAvatar != null)
              GestureDetector(
                onTap: onEditAvatar,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.brandPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Group title + edit pencil if admin
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
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
              if (isAdmin && onEditTitle != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit group name',
                  onPressed: () => _showEditTitleDialog(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Member count
        Text(
          'Group · $memberCount members',
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),

        // Description
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            (description != null && description!.isNotEmpty)
                ? description!
                : (isAdmin ? 'Add group description' : 'No description added'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: secondaryTextColor,
              fontStyle: description == null ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showEditTitleDialog(BuildContext context) {
    final controller = TextEditingController(text: title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter group name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: 'Group name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && onEditTitle != null) {
                onEditTitle!(newName);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
