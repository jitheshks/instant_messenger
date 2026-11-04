import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

/// Reusable avatar selector widget for profile setup and profile editing screens.
class ProfileAvatarSelector extends StatelessWidget {
  final XFile? selectedAvatar;
  final bool isSaving;
  final VoidCallback onTap;

  const ProfileAvatarSelector({
    super.key,
    required this.selectedAvatar,
    required this.isSaving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              GestureDetector(
                onTap: isSaving ? null : onTap,
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: selectedAvatar != null
                      ? FileImage(File(selectedAvatar!.path))
                      : null,
                  child: selectedAvatar == null
                      ? Icon(
                          Icons.person_rounded,
                          size: 58,
                          color: cs.onPrimaryContainer,
                        )
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isSaving ? null : onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 20,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Add a profile photo (optional)',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
