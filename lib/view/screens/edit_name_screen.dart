import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/controller/edit_name_controller.dart';
import 'package:instant_messenger/services/user_bootstrap.dart';
import 'package:provider/provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EditNameScreen extends StatelessWidget {
  final String initial;
  final bool onboarding; // true when opened from first login flow

  const EditNameScreen({
    super.key,
    required this.initial,
    this.onboarding = true, // default for first-time
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('🟣 BUILD → EditNameScreen');

    return ChangeNotifierProvider(
      create: (_) => EditNameScreenController(initialText: initial),
      child: _EditNameView(onboarding: onboarding),
    );
  }
}

class _EditNameView extends StatelessWidget {
  final bool onboarding;
  const _EditNameView({required this.onboarding});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditNameScreenController>();
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        // dismiss keyboard/emoji on background tap
        FocusScope.of(context).unfocus();
        if (c.showEmoji) c.showKeyboard();
      },
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
       appBar: AppBar(
  title: const Text('Name'),
  leading: onboarding ? null : const BackButton(),
),

        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          children: [
            Form(
              child: TextFormField(
                focusNode: c.focusNode,
                controller: c.textController,
                maxLength: 25,
                decoration: InputDecoration(
                  labelText: 'Your name',
                  suffixIcon: IconButton(
                    icon: Icon(c.showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined),
                    onPressed: () => c.toggleEmojiOrKeyboard(context),
                  ),
                  counterText: '${c.textController.text.characters.length}/25',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                autofocus: true,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return "Name can't be empty";
                  if (t.length < 2) return 'Enter at least 2 characters';
                  return null;
                },
                onChanged: (_) {
                  if (c.showEmoji) c.showKeyboard();
                },
                onFieldSubmitted: (_) {
                  // optional: same as pressing Save if you want
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "People will see this name if you interact with them and they don't have you saved as a contact.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
             onPressed: () async {
  final name = c.textController.text.trim();
  if (name.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter at least 2 characters')),
    );
    return;
  }

  try {
    final bootstrap = context.read<UserBootstrap>();

    await bootstrap.setDisplayName(name);

    // 2️⃣ Unlock router + leave onboarding
    if (context.mounted) {
      context.go('/chats');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save name: $e')),
      );
    }
  }
},

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        bottomSheet: c.showEmoji
            ? SafeArea(
                top: false,
                child: SizedBox(
                  height: 300,
                  child: EmojiPicker(
                    textEditingController: c.textController,
                    onEmojiSelected: c.onEmojiSelected,
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
