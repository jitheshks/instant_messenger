import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/profile_notifier.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/avatar_picker_sheet.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';
import 'package:instant_messenger/features/media/data/file_picker_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileView();
}

class _ProfileView extends ConsumerWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileControllerProvider);
    final notifier = ref.read(profileControllerProvider.notifier);

    if (state.loading && !state.hasStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!state.hasStarted) {
          notifier.start();
        }
      });
    }
    if (state.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(child: Text(state.error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), leading: const BackButton()),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          /// ───────── AVATAR ─────────
          Center(
            child: GestureDetector(
              onTap: state.isUploadingAvatar
                  ? null
                  : () => _showAvatarPicker(context, notifier),
              child: SafeAvatar(
                key: ValueKey(state.avatarUrl),
                radius: 54,
                avatarUrl: state.avatarUrl,
                fallbackName: state.displayName,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Center(
            child: OutlinedButton(
              onPressed: state.isUploadingAvatar
                  ? null
                  : () => _showAvatarPicker(context, notifier),
              child: state.isUploadingAvatar
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Edit'),
            ),
          ),

          const SizedBox(height: 16),

          /// ───────── NAME ─────────
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Name'),
            subtitle: Text(state.displayName.isEmpty ? ' ' : state.displayName),
            onTap: () async {
              final edited = await context.push<String>(
                '/editName',
                extra: state.displayName,
              );

              if (edited != null &&
                  edited.trim().isNotEmpty &&
                  edited.trim() != state.displayName) {
                await notifier.updateName(edited.trim());
              }
            },
          ),

          /// ───────── ABOUT ─────────
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text(state.about.isEmpty ? ' ' : state.about),
            onTap: () async {
              final v = await _promptText(context, 'Edit about', state.about);
              if (v != null && v.trim().isNotEmpty) {
                await notifier.updateAbout(v);
              }
            },
          ),

          /// ───────── PHONE ─────────
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(
              state.phoneE164.isEmpty ? 'Not set' : state.phoneE164,
            ),
          ),

          /// ───────── LINKS (DISABLED) ─────────
          ListTile(
            leading: Icon(
              Icons.link_outlined,
              color: Theme.of(context).disabledColor,
            ),
            title: Text(
              'Links',
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
            subtitle: Text(
              state.links.isEmpty ? 'Coming soon' : state.links.join(', '),
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
            enabled: false,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TEXT PROMPT
  // ─────────────────────────────────────────────────────────────
  Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial,
  ) async {
    final ctrl = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // AVATAR PICKER
  // ─────────────────────────────────────────────────────────────
  void _showAvatarPicker(
    BuildContext context,
    ProfileNotifier profileNotifier,
  ) {
    final pageContext = context;
    final dialogContext = Navigator.of(context, rootNavigator: true).context;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => AvatarPickerSheet(
        onGallery: () async {
          final ok = await PermissionService.ensurePhotoRead();
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }

          if (!ok || !pageContext.mounted) return;

          final x = await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          if (!pageContext.mounted) return;

          await _uploadAndSaveAvatar(
            profileNotifier,
            pageContext,
            dialogContext,
            x,
          );
        },
        onCamera: () async {
          final ok = await PermissionService.ensureCamera();
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }

          if (!ok || !pageContext.mounted) return;

          final x = await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          if (!pageContext.mounted) return;

          await _uploadAndSaveAvatar(
            profileNotifier,
            pageContext,
            dialogContext,
            x,
          );
        },
        onAvatar: () {
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
        onAI: () {
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // AVATAR UPLOAD (VOID SAFE)
  // ─────────────────────────────────────────────────────────────
  Future<void> _uploadAndSaveAvatar(
    ProfileNotifier c,
    BuildContext pageContext,
    BuildContext dialogContext,
    XFile x,
  ) async {
    if (!dialogContext.mounted) return;

    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      debugPrint('[UI] calling updateAvatarFromFile');

      // ✅ VOID CALL (FIXED)
      await c.updateAvatarFromFile(x);

      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }

      if (!pageContext.mounted) return;

      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e, st) {
      debugPrint('[UI][Error] $e');
      debugPrintStack(stackTrace: st);

      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }

      if (!pageContext.mounted) return;

      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }
}
