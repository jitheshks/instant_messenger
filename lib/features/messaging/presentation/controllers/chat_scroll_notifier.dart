import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ChatScrollState {
  final bool showJumpButton;
  final int unreadCount;

  const ChatScrollState({this.showJumpButton = false, this.unreadCount = 0});

  ChatScrollState copyWith({bool? showJumpButton, int? unreadCount}) {
    return ChatScrollState(
      showJumpButton: showJumpButton ?? this.showJumpButton,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatScrollNotifier extends Notifier<ChatScrollState> {
  final ScrollController scrollController = ScrollController();
  static const double _awayThreshold = 120;
  bool _attached = false;

  @override
  ChatScrollState build() {
    attach();
    ref.onDispose(() {
      scrollController.removeListener(_onScroll);
      scrollController.dispose();
    });
    return const ChatScrollState();
  }

  bool get showJumpButton => state.showJumpButton;
  int get unreadCount => state.unreadCount;

  void attach() {
    if (_attached) return;
    _attached = true;
    scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final offset = scrollController.position.pixels;
    final isAwayFromBottom = offset > _awayThreshold;

    if (isAwayFromBottom != state.showJumpButton) {
      state = state.copyWith(
        showJumpButton: isAwayFromBottom,
        unreadCount: isAwayFromBottom ? state.unreadCount : 0,
      );
    }
  }

  void jumpToBottom() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    state = state.copyWith(showJumpButton: false, unreadCount: 0);
  }

  void jumpToLatest() => jumpToBottom();

  void onNewIncomingMessage() {
    if (state.showJumpButton) {
      state = state.copyWith(unreadCount: state.unreadCount + 1);
    }
  }

  void onNewMessages(int count) {
    if (state.showJumpButton && count > 0) {
      state = state.copyWith(unreadCount: state.unreadCount + count);
    }
  }
}
