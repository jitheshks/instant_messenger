import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:instant_messenger/controller/chat_screen_controller.dart';
import 'package:instant_messenger/widgets/attachment_sheet.dart';

class ChatInput extends StatelessWidget {
  const ChatInput({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.read<ChatScreenController>();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            // 💬 INPUT PILL
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    // 😀 Emoji
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      onPressed: c.toggleEmojiKeyboard,
                    ),

                    // ✏️ TextField (controller-owned)
                    Expanded(
                      child: TextField(
                        controller: c.input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        onChanged: c.onInputChanged,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),

                    // 📎 File (ALWAYS visible)
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          builder: (_) => AttachmentSheet(controller: c),
                        );
                      },
                    ),

                    // 📷 Camera (Animated hide/show)
                    Selector<ChatScreenController, bool>(
                      selector: (_, ctrl) => ctrl.hasText,
                      builder: (_, hasText, __) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.2, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: hasText
                              ? const SizedBox(
                                  key: ValueKey('no-camera'),
                                  width: 0,
                                )
                              : IconButton(
                                  key: const ValueKey('camera'),
                                  icon:
                                      const Icon(Icons.camera_alt),
                                  onPressed: c.openCamera,
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 6),

            // 🎤 / ➤ SEND (Green floating button)
            Selector<ChatScreenController, bool>(
              selector: (_, ctrl) => ctrl.canSend,
              builder: (_, canSend, __) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: child,
                    );
                  },
                  child: CircleAvatar(
                    key: ValueKey(canSend),
                    radius: 24,
                    backgroundColor:
                        Theme.of(context).primaryColor,
                    child: IconButton(
                      icon: Icon(
                        canSend ? Icons.send : Icons.mic,
                        color: Colors.white,
                      ),
                      onPressed: canSend
                          ? c.sendCurrentText
                          : null,
                      onLongPress:
                          canSend ? null : c.startVoiceRecording,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
