// lib/features/messaging/presentation/widgets/chat_timeline_view.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/call_bubble.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_bubble.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_date_separator.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_timeline_entry.dart';

/// Registry holding GlobalKey references only for currently mounted message bubbles.
///
/// Prevents unbounded memory retention by automatically removing keys when
/// off-screen widgets are recycled by [ListView.builder].
class MessageKeyRegistry {
  final Map<String, GlobalKey> _activeKeys = {};

  GlobalKey register(String messageId) {
    return _activeKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  void unregister(String messageId) {
    _activeKeys.remove(messageId);
  }

  GlobalKey? getKey(String messageId) => _activeKeys[messageId];

  GlobalKey? operator [](String messageId) => _activeKeys[messageId];

  BuildContext? getContext(String messageId) => _activeKeys[messageId]?.currentContext;

  bool isMounted(String messageId) => _activeKeys[messageId]?.currentContext != null;

  void clear() => _activeKeys.clear();
}

/// Host widget that manages the lifecycle of a message bubble's [GlobalKey] in [MessageKeyRegistry].
class _MessageBubbleHost extends StatefulWidget {
  final String messageId;
  final MessageKeyRegistry registry;
  final Widget child;

  const _MessageBubbleHost({
    required Key key,
    required this.messageId,
    required this.registry,
    required this.child,
  }) : super(key: key);

  @override
  State<_MessageBubbleHost> createState() => _MessageBubbleHostState();
}

class _MessageBubbleHostState extends State<_MessageBubbleHost> {
  late GlobalKey _key;

  @override
  void initState() {
    super.initState();
    _key = widget.registry.register(widget.messageId);
  }

  @override
  void dispose() {
    widget.registry.unregister(widget.messageId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// Virtualized timeline view rendering chat messages, in-chat call events,
/// date separators, and older-history loading spinners.
///
/// Lazily builds only visible viewport items using [ListView.builder] with
/// reverse ordering, bounded GlobalKey tracking, and reliable quote scrolling.
class ChatTimelineView extends ConsumerStatefulWidget {
  final ChatControllerArgs chatArgs;
  final String currentUserId;
  final String peerUserId;
  final String contactName;
  final String contactAvatar;
  final ScrollController scrollController;
  final ChatTimelineState timelineState;
  final ChatTimelineNotifier timelineNotifier;
  final Set<String> selectionState;
  final ChatScreenSelectionNotifier selectionNotifier;
  final List<CallRecord> calls;
  final void Function(ChatMessage message) onSwipeReply;
  final void Function(CallRecord call) onCallBack;

  const ChatTimelineView({
    super.key,
    required this.chatArgs,
    required this.currentUserId,
    required this.peerUserId,
    required this.contactName,
    required this.contactAvatar,
    required this.scrollController,
    required this.timelineState,
    required this.timelineNotifier,
    required this.selectionState,
    required this.selectionNotifier,
    required this.calls,
    required this.onSwipeReply,
    required this.onCallBack,
  });

  @override
  ConsumerState<ChatTimelineView> createState() => ChatTimelineViewState();
}

class ChatTimelineViewState extends ConsumerState<ChatTimelineView> {
  final MessageKeyRegistry _keyRegistry = MessageKeyRegistry();
  DateTime? _lastPaginationTime;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  ScrollController? _attachedController;
  VoidCallback? _scrollListener;

  @override
  void initState() {
    super.initState();
    _attachScrollPagination();
  }

  @override
  void didUpdateWidget(covariant ChatTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollPagination();
      _attachScrollPagination();
    }
  }

  void _attachScrollPagination() {
    final controller = widget.scrollController;
    _attachedController = controller;
    _scrollListener = () {
      if (!mounted || !controller.hasClients) return;
      final pos = controller.position;

      // In reverse ListView:
      // pixels == 0 is bottom (newest items).
      // pixels == maxScrollExtent is top (oldest items).
      if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 250.0) {
        final now = DateTime.now();
        if (_lastPaginationTime != null &&
            now.difference(_lastPaginationTime!) < const Duration(milliseconds: 350)) {
          return;
        }
        _lastPaginationTime = now;

        try {
          if (widget.timelineNotifier.hasMore &&
              !widget.timelineNotifier.loadingMore &&
              widget.timelineNotifier.lastSentAt != null) {
            widget.timelineNotifier.loadOlder();
          }
        } catch (e) {
          debugPrint('[ChatTimelineView] Scroll pagination skipped: $e');
        }
      }
    };

    controller.addListener(_scrollListener!);
  }

  void _detachScrollPagination() {
    if (_attachedController != null && _scrollListener != null) {
      _attachedController!.removeListener(_scrollListener!);
      _attachedController = null;
      _scrollListener = null;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _detachScrollPagination();
    _keyRegistry.clear();
    super.dispose();
  }

  /// Scrolls to and highlights the target message.
  ///
  /// Uses direct [Scrollable.ensureVisible] if the widget is mounted;
  /// otherwise calculates a proportional offset to bring the virtualized item
  /// into view before refining alignment.
  void scrollToMessage(String messageId, List<TimelineEntry> entries) {
    final targetIndex = entries.indexWhere(
      (e) => e is MessageTimelineEntry && e.message.id == messageId,
    );

    if (targetIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Original message not loaded')),
        );
      }
      return;
    }

    final controller = widget.scrollController;
    if (!controller.hasClients) return;

    // Stage 1: If element is currently mounted in viewport, scroll directly
    final mountedContext = _keyRegistry.getContext(messageId);
    if (mountedContext != null) {
      Scrollable.ensureVisible(
        mountedContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
      _highlightTargetMessage(messageId);
      return;
    }

    // Stage 2: Staged scrolling for virtualized off-screen items
    final total = entries.length;
    final ratio = total > 1 ? (targetIndex / (total - 1)) : 0.0;
    final maxScroll = controller.position.maxScrollExtent;
    final targetOffset = (ratio * maxScroll).clamp(0.0, maxScroll);

    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _keyRegistry.getContext(messageId);
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
        _highlightTargetMessage(messageId);
      });
    });
  }

  void _highlightTargetMessage(String messageId) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timelineState = widget.timelineState;
    final timelineNotifier = widget.timelineNotifier;

    // 1. Initial load in progress
    if (timelineNotifier.initInProgress && !timelineState.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Initial load error
    if (timelineState.hasInitError && !timelineState.isReady) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 8),
            Text(
              'Failed to load chat: ${timelineState.initError}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                timelineNotifier.clearInitError();
                timelineNotifier.ensureInit(
                  otherName: widget.contactName,
                  otherAvatar: widget.contactAvatar.isEmpty
                      ? null
                      : widget.contactAvatar,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // 3. Ready state: Compile virtualized timeline entries
    if (timelineState.isReady) {
      final msgs = timelineState.messages;
      final calls = widget.calls;

      if (msgs.isEmpty && calls.isEmpty) {
        final cs = Theme.of(context).colorScheme;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No messages yet',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  timelineNotifier.ensureInit(
                    otherName: widget.contactName,
                    otherAvatar: widget.contactAvatar.isEmpty
                        ? null
                        : widget.contactAvatar,
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              if (timelineState.hasInitError) ...[
                const SizedBox(height: 8),
                Text(
                  'Last error: ${timelineState.initError}',
                  style: TextStyle(color: cs.error),
                ),
              ],
            ],
          ),
        );
      }

      // Mark incoming messages as read
      if (msgs.any((m) => m.isIncoming && !m.isRead)) {
        timelineNotifier.maybeMarkRead();
      }

      final entries = buildTimelineEntries(
        messages: msgs,
        calls: calls,
        loadingMore: timelineState.loadingMore,
      );

      final now = DateTime.now();

      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        controller: widget.scrollController,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];

          switch (entry) {
            case LoadingMoreTimelineEntry():
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );

            case DateSeparatorTimelineEntry(:final date):
              return ChatDateSeparator(date: date, now: now);

            case CallTimelineEntry(:final call):
              return CallBubble(
                call: call,
                currentUserId: widget.currentUserId,
                onCallBack: () => widget.onCallBack(call),
              );

            case MessageTimelineEntry(:final message):
              final isSelected = widget.selectionState.contains(message.id);
              final isHighlighted = _highlightedMessageId == message.id;

              return _MessageBubbleHost(
                key: ValueKey('host_${message.id}'),
                messageId: message.id,
                registry: _keyRegistry,
                child: GestureDetector(
                  onTap: () {
                    if (widget.selectionState.isNotEmpty) {
                      widget.selectionNotifier.toggle(message.id);
                    }
                  },
                  onLongPress: () {
                    widget.selectionNotifier.toggle(message.id);
                  },
                  child: ChatBubble(
                    msg: message,
                    isMe: message.senderId == widget.currentUserId,
                    isSelected: isSelected || isHighlighted,
                    onSwipeReply: widget.selectionState.isEmpty
                        ? () => widget.onSwipeReply(message)
                        : null,
                    onTapQuote: (quoteMsgId) =>
                        scrollToMessage(quoteMsgId, entries),
                    onRetry: message.canRetry
                        ? () {
                            ref
                                .read(chatSendNotifierProvider(widget.chatArgs).notifier)
                                .retryMessage(message.id);
                          }
                        : null,
                    onCancel: (message.type == MessageType.media &&
                            message.uploadProgress != null &&
                            !message.hasFailed)
                        ? () {
                            ref
                                .read(chatSendNotifierProvider(widget.chatArgs).notifier)
                                .cancelMediaMessage(message.id);
                          }
                        : null,
                  ),
                ),
              );
          }
        },
      );
    }

    return const Center(child: CircularProgressIndicator());
  }
}
