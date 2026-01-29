import 'package:flutter/material.dart';

class AvatarPickerSheet extends StatelessWidget {
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;
  final VoidCallback? onAvatar;
  final VoidCallback? onAI;

  const AvatarPickerSheet({
    super.key,
    this.onCamera,
    this.onGallery,
    this.onAvatar,
    this.onAI,
  });

  void _safePopThen(BuildContext context, VoidCallback? cb) {
    Navigator.of(context).pop();
    if (cb != null) cb();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          const SizedBox(height: 8),
          Container(
            height: 4,
            width: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // header row with close icon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Text(
                    'Profile photo',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 48), // balance close button width
              ],
            ),
          ),

          // actions
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () => _safePopThen(context, onCamera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => _safePopThen(context, onGallery),
          ),
          ListTile(
            leading: const Icon(Icons.face_outlined),
            title: const Text('Avatar'),
            onTap: () => _safePopThen(context, onAvatar),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI images'),
            onTap: () => _safePopThen(context, onAI),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
