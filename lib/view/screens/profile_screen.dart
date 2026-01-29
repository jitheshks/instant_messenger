import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/services/permission_service.dart';
import 'package:instant_messenger/widgets/avatar_picker_sheet.dart';
import 'package:instant_messenger/widgets/safe_avatar.dart';
import 'package:provider/provider.dart';

import '../../controller/profile_controller.dart';
import 'package:instant_messenger/services/file_picker_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileView();
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProfileController?>();

if (c == null) {
  return Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: const Center(child: CircularProgressIndicator()),
  );
}

  if (c.loading && !c.hasStarted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasStarted) {
        c.start();
      }
    });
  }
if (c.loading) {
  return Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: const Center(child: CircularProgressIndicator()),
  );
}


    if (c.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(child: Text(c.error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: const BackButton(),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          /// ───────── AVATAR ─────────
          Center(
            child: GestureDetector(
  onTap: c.isUploadingAvatar ? null : () => _showAvatarPicker(context),
  child: SafeAvatar(
    key: ValueKey(c.avatarUrl),
    radius: 54,
    avatarUrl: c.avatarUrl,
    fallbackName: c.displayName,
  ),
),

          ),

          const SizedBox(height: 12),

          Center(
            child: OutlinedButton(
  onPressed: c.isUploadingAvatar ? null : () => _showAvatarPicker(context),
  child: c.isUploadingAvatar
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
            subtitle: Text(c.displayName.isEmpty ? ' ' : c.displayName),
            onTap: () async {
              final edited =
                  await context.push<String>('/editName', extra: c.displayName);

              if (edited != null &&
                  edited.trim().isNotEmpty &&
                  edited.trim() != c.displayName) {
                await c.updateName(edited.trim());
              }
            },
          ),

          /// ───────── ABOUT ─────────
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text(c.about.isEmpty ? ' ' : c.about),
            onTap: () async {
              final v = await _promptText(context, 'Edit about', c.about);
              if (v != null && v.trim().isNotEmpty) {
                await c.updateAbout(v);
              }
            },
          ),

          /// ───────── PHONE ─────────
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(c.phoneE164.isEmpty ? 'Not set' : c.phoneE164),
          ),

          /// ───────── LINKS (DISABLED) ─────────
          ListTile(
            leading: Icon(Icons.link_outlined,
                color: Theme.of(context).disabledColor),
            title: Text(
              'Links',
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
            subtitle: Text(
              c.links.isEmpty ? 'Coming soon' : c.links.join(', '),
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
  void _showAvatarPicker(BuildContext context) {
    final pageContext = context;
    final nav = Navigator.of(context);

final profileController = context.read<ProfileController?>();

if (profileController == null) return;
    final dialogContext =
        Navigator.of(context, rootNavigator: true).context;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => AvatarPickerSheet(
        onGallery: () async {
          final ok = await PermissionService.ensurePhotoRead();
          nav.pop();

          if (!ok || !pageContext.mounted) return;

          final x =
              await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          await _uploadAndSaveAvatar(
            profileController,
            pageContext,
            dialogContext,
            x,
          );
        },
        onCamera: () async {
          final ok = await PermissionService.ensureCamera();
          nav.pop();

          if (!ok || !pageContext.mounted) return;

          final x =
              await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          await _uploadAndSaveAvatar(
            profileController,
            pageContext,
            dialogContext,
            x,
          );
        },
        onAvatar: () => nav.pop(),
        onAI: () => nav.pop(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // AVATAR UPLOAD (VOID SAFE)
  // ─────────────────────────────────────────────────────────────
  Future<void> _uploadAndSaveAvatar(
    ProfileController c,
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

      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e, st) {
      debugPrint('[UI][Error] $e');
      debugPrintStack(stackTrace: st);

      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }

      if (!pageContext.mounted) return;

      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }
}
