import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/media/presentation/widgets/attachment_sheet.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/reply_composer_preview.dart';

class ChatInput extends ConsumerStatefulWidget {
  final ChatControllerArgs args;
  final String otherName;
  final String? otherAvatar;

  const ChatInput({
    super.key,
    required this.args,
    required this.otherName,
    this.otherAvatar,
  });

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    ref
        .read(chatTypingNotifierProvider(widget.args).notifier)
        .onTypingChanged(_textController.text);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    ref.read(chatTypingNotifierProvider(widget.args).notifier).clearTyping();

    ref
        .read(chatSendNotifierProvider(widget.args).notifier)
        .sendText(
          text,
          otherName: widget.otherName,
          otherAvatar: widget.otherAvatar,
        );
  }

  void _openAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AttachmentSheet(
        args: widget.args,
        otherName: widget.otherName,
        otherAvatar: widget.otherAvatar,
        sendNotifier: ref.read(chatSendNotifierProvider(widget.args).notifier),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatSendState>(chatSendNotifierProvider(widget.args), (
      prev,
      next,
    ) {
      if (next.error != null && next.error != prev?.error && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: ${next.error}')),
        );
      }
      if (next.hasReplyTarget && !(prev?.hasReplyTarget ?? false)) {
        _focusNode.requestFocus();
      }
    });
    final sendState = ref.watch(chatSendNotifierProvider(widget.args));

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatTheme = ChatThemeExtension.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sendState.hasReplyTarget)
              ReplyComposerPreview(
                replyTarget: sendState.replyTarget!,
                senderName:
                    sendState.replyTargetSenderName ??
                    (sendState.replyTarget!.senderId ==
                            widget.args.currentUserId
                        ? 'You'
                        : widget.otherName),
                onCancel: () {
                  ref
                      .read(chatSendNotifierProvider(widget.args).notifier)
                      .clearReplyTarget();
                },
              ),
            Row(
              children: [
                // 💬 INPUT PILL
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: chatTheme.inputBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? Colors.transparent
                            : cs.outlineVariant,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        // 😀 Emoji
                        IconButton(
                          icon: Icon(
                            Icons.emoji_emotions_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () {
                            if (_focusNode.hasFocus) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          },
                        ),

                        // ✏️ TextField
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(color: cs.onSurface, fontSize: 16),
                            cursorColor: cs.primary,
                            decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                color: chatTheme.inputHint,
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),

                        // 📎 File (ALWAYS visible)
                        IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: _openAttachmentSheet,
                        ),

                        // 📷 Camera (Animated hide/show)
                        AnimatedSwitcher(
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
                          child: _hasText
                              ? const SizedBox(
                                  key: ValueKey('no-camera'),
                                  width: 0,
                                )
                              : IconButton(
                                  key: const ValueKey('camera'),
                                  icon: Icon(
                                    Icons.camera_alt,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    debugPrint('[UI] Camera opened');
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Modern Iris send action button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Container(
                    key: ValueKey(_hasText),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        _hasText ? Icons.send : Icons.mic,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _hasText ? _send : null,
                      onLongPress: _hasText
                          ? null
                          : () {
                              debugPrint('[Voice] Start recording');
                            },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
