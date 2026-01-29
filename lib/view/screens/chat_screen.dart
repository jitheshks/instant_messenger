import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:instant_messenger/controller/chat_screen_controller.dart';
import 'package:instant_messenger/controller/chat_screen_selection_controller.dart';
import 'package:instant_messenger/controller/chat_scroll_controller.dart';
import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/models/user_presence.dart';
import 'package:instant_messenger/utils/chat_date.dart';
import 'package:instant_messenger/widgets/app_bar_header.dart';
import 'package:instant_messenger/widgets/chat_bubble.dart';
import 'package:instant_messenger/widgets/chat_input.dart';
import 'package:instant_messenger/widgets/jump_to_latest_button.dart';
import 'package:instant_messenger/widgets/typing_dots.dart';

class ChatScreen extends StatelessWidget {
  final String chatId;
  final String currentUserId;
  final String peerUserId; // ✅ ADD THIS
  final String contactName;
  final String contactAvatar;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.peerUserId,
    required this.contactName,
    required this.contactAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatScrollController()),
        ChangeNotifierProvider(create: (_) => ChatScreenSelectionController()),
      ],
      child: _ChatScreenBody(
        chatId: chatId,
        currentUserId: currentUserId,
        contactName: contactName,
        contactAvatar: contactAvatar,
      ),
    );
  }
}

class _ChatScreenBody extends StatelessWidget {
  final String chatId;
  final String currentUserId;
  final String contactName;
  final String contactAvatar;

  const _ChatScreenBody({
    required this.chatId,
    required this.currentUserId,
    required this.contactName,
    required this.contactAvatar,
  });

  void _ensureInitOnce(BuildContext context) {
    final controller = context.read<ChatScreenController>();

    // ✅ Safety guard
    if (controller.initInProgress || controller.isReady) return;

    if (kDebugMode) {
      debugPrint('[ChatUI] ensureInit chatId=$chatId');
    }

    // ✅ Run right AFTER build, but BEFORE next frame
    Future.microtask(() {
      if (controller.initInProgress || controller.isReady) return;

      controller.ensureInit(
        otherName: contactName,
        otherAvatar: contactAvatar.isEmpty ? null : contactAvatar,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ RESOLVE CONTROLLERS ONCE
    final chatCtrl = context.watch<ChatScreenController>();
    final scrollCtrl = context.watch<ChatScrollController>();
    final selectionCtrl = context.watch<ChatScreenSelectionController>();

    // ✅ One-time binding (safe, idempotent)
    Future.microtask(() {
      chatCtrl.bindScrollController(scrollCtrl);
      scrollCtrl.attach();
    });

    // ✅ ensure init
    _ensureInitOnce(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Intentionally empty
        // GoRouter + Navigator handle predictive back
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selectionCtrl.active
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: selectionCtrl.clear,
                )
              : null,
          titleSpacing: 0,
          title: selectionCtrl.active
              ? Text(
                  '${selectionCtrl.count}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              : AppBarHeader(
                  title: contactName,
                  avatarUrl: contactAvatar.isEmpty ? null : contactAvatar,
                  radius: 16,

                  subtitle: !chatCtrl.isReady
                      ? const SizedBox.shrink()
                      : StreamBuilder<bool>(
                          stream: chatCtrl.watchTyping(chatCtrl.otherUserId),

                          builder: (context, typingSnap) {
                            final isTyping = typingSnap.data == true;

                            return StreamBuilder<UserPresence>(
                              stream: chatCtrl.watchPresence(
                                chatCtrl.otherUserId,
                              ),

                              builder: (context, presenceSnap) {
                                if (!chatCtrl.presenceReady) {
                                  return const SizedBox.shrink();
                                }

                                final presence = presenceSnap.data;

                                Widget subtitleWidget;

                                if (isTyping) {
                                  subtitleWidget = const TypingDots();
                                } else if (presence != null &&
                                    presence.online) {
                                  subtitleWidget = Text(
                                    presenceSubtitle(presence),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  );
                                } else {
                                  subtitleWidget = const SizedBox.shrink();
                                }

                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: subtitleWidget is SizedBox
                                      ? const SizedBox(key: ValueKey('empty'))
                                      : Container(
                                          key: const ValueKey('visible'),
                                          child: subtitleWidget,
                                        ),
                                );
                              },
                            );
                          },
                        ),
                ),

          actions: selectionCtrl.active
              ? _buildSelectionActions(selectionCtrl)
              : _buildNormalActions(context),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildBodyContent(
                    context,
                    chatCtrl,
                    selectionCtrl,
                    scrollCtrl, // 👈 PASS IT
                  ),
                  const JumpToLatestButton(),
                ],
              ),
            ),

            Visibility(
              visible: chatCtrl.isReady,
              replacement: const SizedBox.shrink(),
              child: const ChatInput(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    ChatScreenController chatCtrl,
    ChatScreenSelectionController selectionCtrl,
    ChatScrollController scrollCtrl,
  ) {
    // 1) init in progress -> spinner
    if (chatCtrl.initInProgress && !chatCtrl.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2) init error -> retry UI
    if (chatCtrl.hasInitError && !chatCtrl.isReady) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 8),
            Text(
              'Failed to load chat: ${chatCtrl.initErrorPublic}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                chatCtrl.clearInitError();
                chatCtrl.ensureInit(
                  otherName: contactName,
                  otherAvatar: contactAvatar.isEmpty ? null : contactAvatar,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // 3) ready -> show messages stream
    if (chatCtrl.isReady) {
      return StreamBuilder<List<ChatMessage>>(
        stream: chatCtrl.stream,
        builder: (context, snap) {
          if (kDebugMode) {
            debugPrint(
              '[ChatStream] connectionState=${snap.connectionState} '
              'hasData=${snap.hasData} hasError=${snap.hasError}',
            );
          }

          if (snap.hasError) {
            if (kDebugMode) {
              debugPrint('[ChatStream] stream error: ${snap.error}');
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load messages: ${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      // retry init which will re-attach stream when controller is ready
                      chatCtrl.ensureInit(
                        otherName: contactName,
                        otherAvatar: contactAvatar.isEmpty
                            ? null
                            : contactAvatar,
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final msgs = snap.data ?? const <ChatMessage>[];
          final now = DateTime.now();

          // No messages yet
          if (msgs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      chatCtrl.ensureInit(
                        otherName: contactName,
                        otherAvatar: contactAvatar.isEmpty
                            ? null
                            : contactAvatar,
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  if (chatCtrl.hasInitError) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last error: ${chatCtrl.initErrorPublic}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            );
          }

          // Use controller.maybeMarkRead (controller handles debounce/state)
          final newest = msgs.isNotEmpty ? msgs.last : null;
          if (newest != null && newest.isIncoming && !newest.isRead) {
            chatCtrl.maybeMarkRead(newest);
          }

          // build list + date separators
          final items = <Widget>[];
          String? lastDayKey;
          for (final msg in msgs) {
            final key = dayKey(msg.sentAt);
            if (lastDayKey != key) {
              items.add(
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      chatDateLabel(msg.sentAt, now),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
              lastDayKey = key;
            }

            final isSelected = selectionCtrl.isSelected(msg.id);
            items.add(
              GestureDetector(
                onTap: () {
                  if (selectionCtrl.active) {
                    selectionCtrl.toggle(msg.id);
                  }
                },
                onLongPress: () => selectionCtrl.toggle(msg.id),
                child: ChatBubble(
                  msg: msg,
                  isMe: msg.senderId == chatCtrl.currentUserId,
                  isSelected: isSelected,
                  onRetry: msg.canRetry
                      ? () {
                          debugPrint('[UI] Retry tapped for ${msg.id}');
                          chatCtrl.retryMediaMessage(msg.id);
                        }
                      : null,

                  // ❌ Cancel (NEW)
                  onCancel:
                      (msg.type == MessageType.media &&
                          msg.uploadProgress != null &&
                          !msg.hasFailed)
                      ? () {
                          debugPrint('[UI] Cancel tapped for ${msg.id}');
                          chatCtrl.cancelMediaMessage(msg.id);
                        }
                      : null,
                ),
              ),
            );
          }
          return ListView(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            controller: scrollCtrl.scrollController,
            children: items.reversed.toList(),
          );
        },
      );
    }

    // default fallback (shouldn't normally get here)
    return const Center(child: CircularProgressIndicator());
  }

  List<Widget> _buildSelectionActions(
    ChatScreenSelectionController selectionController,
  ) {
    return [
      if (selectionController.count == 1)
        IconButton(icon: const Icon(Icons.reply), onPressed: () {}),
      IconButton(icon: const Icon(Icons.star_border), onPressed: () {}),
      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
      if (selectionController.count > 1)
        IconButton(icon: const Icon(Icons.content_copy), onPressed: () {}),
      if (selectionController.count == 1)
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
    ];
  }

  List<Widget> _buildNormalActions(BuildContext context) {
    const disabledColor = Colors.grey;

    return [
      // 📹 Video call (disabled)
      IconButton(
        icon: const Icon(Icons.videocam_outlined, color: disabledColor),
        onPressed: () => _showUnavailable(context),
        tooltip: 'Video call (coming soon)',
      ),

      // 📞 Voice call (disabled)
      IconButton(
        icon: const Icon(Icons.call_outlined, color: disabledColor),
        onPressed: () => _showUnavailable(context),
        tooltip: 'Voice call (coming soon)',
      ),

      // ⋮ More (keep disabled or null)
      IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: null, // keeps Material disabled look
      ),
    ];
  }

  void _showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Temporarily unavailable'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
