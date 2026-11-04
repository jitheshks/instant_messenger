// lib/features/messaging/presentation/screens/chat_screen.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_app_bar.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_app_bar_actions.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_input.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_timeline_view.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/forward_recipient_sheet.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/jump_to_latest_button.dart';

/// Screen-level coordinator for active one-on-one and group chat conversations.
class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String currentUserId;
  final String peerUserId;
  final String contactName;
  final String contactAvatar;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.peerUserId,
    required this.contactName,
    required this.contactAvatar,
    this.isGroup = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  void _ensureInitOnce(ChatTimelineNotifier notifier, ChatTimelineState state) {
    if (notifier.initInProgress || state.isReady) return;

    if (kDebugMode) {
      debugPrint('[ChatUI] ensureInit chatId=${widget.chatId}');
    }

    Future.microtask(() {
      if (notifier.initInProgress || state.isReady) return;

      notifier.ensureInit(
        otherName: widget.contactName,
        otherAvatar: widget.contactAvatar.isEmpty ? null : widget.contactAvatar,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatArgs = ChatControllerArgs(
      chatId: widget.chatId,
      currentUserId: widget.currentUserId,
      otherUserId: widget.peerUserId,
      isGroup: widget.isGroup,
    );

    final timelineState = ref.watch(chatTimelineNotifierProvider(chatArgs));
    final timelineNotifier = ref.read(
      chatTimelineNotifierProvider(chatArgs).notifier,
    );
    final scrollNotifier = ref.read(chatScrollControllerProvider.notifier);
    final selectionState = ref.watch(chatScreenSelectionControllerProvider);
    final selectionNotifier = ref.read(
      chatScreenSelectionControllerProvider.notifier,
    );
    final isTyping = ref.watch(chatTypingNotifierProvider(chatArgs));
    final presenceAsync = ref.watch(
      chatPresenceStreamProvider(widget.peerUserId),
    );
    final chatCallsAsync = ref.watch(chatCallsProvider(widget.chatId));

    Future.microtask(() {
      scrollNotifier.attach();
    });

    _ensureInitOnce(timelineNotifier, timelineState);

    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.go('/chats');
        }
      },
      child: Scaffold(
        appBar: ChatAppBar(
          ref: ref,
          chatArgs: chatArgs,
          contactName: widget.contactName,
          contactAvatar: widget.contactAvatar,
          isGroup: widget.isGroup,
          isTimelineReady: timelineState.isReady,
          isTyping: isTyping,
          presenceAsync: presenceAsync,
          timelineState: timelineState,
          selectionState: selectionState,
          selectionNotifier: selectionNotifier,
          onSetReply: (msg) => _setReplyTarget(msg, chatArgs),
          onOpenForwardSheet: (msgs) =>
              _openForwardSheet(context, msgs, selectionNotifier),
          onCopyMessages: (msgs) =>
              _copySelectedMessages(msgs, selectionNotifier),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ChatTimelineView(
                    chatArgs: chatArgs,
                    currentUserId: widget.currentUserId,
                    peerUserId: widget.peerUserId,
                    contactName: widget.contactName,
                    contactAvatar: widget.contactAvatar,
                    scrollController: scrollNotifier.scrollController,
                    timelineState: timelineState,
                    timelineNotifier: timelineNotifier,
                    selectionState: selectionState,
                    selectionNotifier: selectionNotifier,
                    calls: chatCallsAsync.value ?? const [],
                    onSwipeReply: (msg) => _setReplyTarget(msg, chatArgs),
                    onCallBack: (call) {
                      ChatAppBarActions.initiateCall(
                        context,
                        ref,
                        widget.chatId,
                        widget.peerUserId,
                        widget.contactName,
                        call.callType,
                      );
                    },
                  ),
                  const JumpToLatestButton(),
                ],
              ),
            ),
            Visibility(
              visible: timelineState.isReady,
              replacement: const SizedBox.shrink(),
              child: ChatInput(
                args: chatArgs,
                otherName: widget.contactName,
                otherAvatar: widget.contactAvatar.isEmpty
                    ? null
                    : widget.contactAvatar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setReplyTarget(ChatMessage msg, ChatControllerArgs chatArgs) {
    final senderName = msg.senderId == widget.currentUserId
        ? 'You'
        : widget.contactName;
    ref
        .read(chatSendNotifierProvider(chatArgs).notifier)
        .setReplyTarget(msg, senderName: senderName);
  }

  Future<void> _openForwardSheet(
    BuildContext context,
    List<ChatMessage> messages,
    ChatScreenSelectionNotifier selectionNotifier,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final didForward = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ForwardRecipientSheet(messages: messages),
    );

    if (didForward == true && mounted) {
      selectionNotifier.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            messages.length == 1
                ? 'Message forwarded'
                : '${messages.length} messages forwarded',
          ),
        ),
      );
    }
  }

  Future<void> _copySelectedMessages(
    List<ChatMessage> selectedMsgs,
    ChatScreenSelectionNotifier selectionNotifier,
  ) async {
    final textMsgs = selectedMsgs
        .where((m) => m.text.trim().isNotEmpty)
        .toList();
    if (textMsgs.isEmpty) return;

    final combinedText = textMsgs.map((m) => m.text).join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: combinedText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              textMsgs.length == 1
                  ? 'Message copied'
                  : '${textMsgs.length} messages copied',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        selectionNotifier.clear();
      }
    } catch (e) {
      debugPrint('[ChatScreen] Clipboard copy error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
