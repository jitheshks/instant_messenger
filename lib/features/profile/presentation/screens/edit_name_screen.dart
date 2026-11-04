import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:instant_messenger/features/media/data/file_picker_service.dart';
import 'package:instant_messenger/features/media/presentation/providers/media_providers.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/avatar_picker_sheet.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_avatar_selector.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EditNameScreen extends ConsumerWidget {
  final String initial;
  final bool onboarding; // true when opened from first login flow

  const EditNameScreen({
    super.key,
    required this.initial,
    this.onboarding = true,
  });

  void _showAvatarPicker(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final nav = Navigator.of(context);
    final notifier = ref.read(editNameControllerFamily(initial).notifier);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => AvatarPickerSheet(
        onGallery: () async {
          final ok = await PermissionService.ensurePhotoRead();
          nav.pop();

          if (!ok || !pageContext.mounted) return;

          final x = await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          notifier.setSelectedAvatar(x);
        },
        onCamera: () async {
          final ok = await PermissionService.ensureCamera();
          nav.pop();

          if (!ok || !pageContext.mounted) return;

          final x = await FilePickerService.pickAndCropAvatar(pageContext);
          if (x == null || !File(x.path).existsSync()) return;

          notifier.setSelectedAvatar(x);
        },
        onAvatar: () => nav.pop(),
        onAI: () => nav.pop(),
      ),
    );
  }

  Future<void> _handleSave(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final notifier = ref.read(editNameControllerFamily(initial).notifier);
    final state = ref.read(editNameControllerFamily(initial));

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Name can't be empty")));
      return;
    }
    if (name.length < 2) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 2 characters')),
      );
      return;
    }

    notifier.setSaving(true);
    String? uploadedAvatarUrl;

    try {
      final uid = SupabaseConfig.currentUserId;

      // 1. Upload avatar if selected
      if (state.selectedAvatar != null && uid != null && uid.isNotEmpty) {
        final orchestrator = ref.read(uploadOrchestratorProvider);
        if (orchestrator != null) {
          try {
            uploadedAvatarUrl = await orchestrator.uploadAvatar(
              ownerType: 'user',
              ownerId: uid,
              filePath: state.selectedAvatar!.path,
            );
          } catch (uploadErr) {
            debugPrint('[EditNameScreen] Avatar upload failed: $uploadErr');
          }
        }
      }

      // 2. Persist profile update via UserBootstrap / UserService
      final bootstrap = ref.read(userBootstrapProvider);
      await bootstrap.setDisplayName(name, avatarUrl: uploadedAvatarUrl);

      // 3. Mark name requirement complete in RouterNotifier
      ref.read(routerNotifierProvider).setRequiresName(false);

      if (!context.mounted) return;

      if (onboarding) {
        context.go('/chats');
      } else {
        Navigator.of(context).pop(name);
      }
    } catch (e) {
      debugPrint('[EditNameScreen] Save profile error: $e');
      notifier.setSaving(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('🟣 BUILD → EditNameScreen (onboarding=$onboarding)');

    final state = ref.watch(editNameControllerFamily(initial));
    final notifier = ref.read(editNameControllerFamily(initial).notifier);
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (state.showEmoji) notifier.showKeyboard();
      },
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        appBar: AppBar(
          title: Text(onboarding ? 'Profile Setup' : 'Name'),
          leading: onboarding ? null : const BackButton(),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          children: [
            // Profile photo selector
            ProfileAvatarSelector(
              selectedAvatar: state.selectedAvatar,
              isSaving: state.isSaving,
              onTap: () => _showAvatarPicker(context, ref),
            ),
            const SizedBox(height: 28),

            // Required display name input
            Form(
              child: TextFormField(
                focusNode: notifier.focusNode,
                controller: notifier.textController,
                maxLength: 25,
                enabled: !state.isSaving,
                decoration: InputDecoration(
                  labelText: 'Your name *',
                  hintText: 'Enter your name',
                  suffixIcon: IconButton(
                    icon: Icon(
                      state.showEmoji
                          ? Icons.keyboard
                          : Icons.emoji_emotions_outlined,
                    ),
                    onPressed: state.isSaving
                        ? null
                        : () => notifier.toggleEmojiOrKeyboard(context),
                  ),
                  counterText:
                      '${notifier.textController.text.characters.length}/25',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return "Name can't be empty";
                  if (t.length < 2) return 'Enter at least 2 characters';
                  return null;
                },
                onChanged: (_) {
                  if (state.showEmoji) notifier.showKeyboard();
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "People will see this name if you interact with them and they don't have you saved as a contact.",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),

            // Save / Continue Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: state.isSaving
                    ? null
                    : () => _handleSave(
                        context,
                        ref,
                        notifier.textController.text.trim(),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: state.isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Save & Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        bottomSheet: state.showEmoji
            ? SafeArea(
                top: false,
                child: SizedBox(
                  height: 300,
                  child: EmojiPicker(
                    textEditingController: notifier.textController,
                    onEmojiSelected: notifier.onEmojiSelected,
                    onBackspacePressed: () {},
                    config: const Config(),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
