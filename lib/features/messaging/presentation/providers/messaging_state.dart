import 'package:flutter/foundation.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// State of the chat timeline message list, loading, and pagination.
@immutable
class ChatTimelineState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isReady;
  final bool hasMore;
  final bool loadingMore;
  final String? initError;
  final DateTime? lastSentAt;

  const ChatTimelineState({
    this.messages = const [],
    this.isLoading = true,
    this.isReady = false,
    this.hasMore = true,
    this.loadingMore = false,
    this.initError,
    this.lastSentAt,
  });

  bool get hasInitError => initError != null;

  ChatTimelineState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isReady,
    bool? hasMore,
    bool? loadingMore,
    String? initError,
    bool clearError = false,
    DateTime? lastSentAt,
  }) {
    return ChatTimelineState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isReady: isReady ?? this.isReady,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      initError: clearError ? null : (initError ?? this.initError),
      lastSentAt: lastSentAt ?? this.lastSentAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatTimelineState &&
          runtimeType == other.runtimeType &&
          listEquals(messages, other.messages) &&
          isLoading == other.isLoading &&
          isReady == other.isReady &&
          hasMore == other.hasMore &&
          loadingMore == other.loadingMore &&
          initError == other.initError &&
          lastSentAt == other.lastSentAt;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(messages),
        isLoading,
        isReady,
        hasMore,
        loadingMore,
        initError,
        lastSentAt,
      );
}

/// State of message sending actions.
@immutable
class ChatSendState {
  final bool isSending;
  final String? error;
  final ChatMessage? replyTarget;
  final String? replyTargetSenderName;

  const ChatSendState({
    this.isSending = false,
    this.error,
    this.replyTarget,
    this.replyTargetSenderName,
  });

  bool get hasReplyTarget => replyTarget != null;

  ChatSendState copyWith({
    bool? isSending,
    String? error,
    bool clearError = false,
    ChatMessage? replyTarget,
    String? replyTargetSenderName,
    bool clearReplyTarget = false,
  }) {
    return ChatSendState(
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      replyTarget: clearReplyTarget ? null : (replyTarget ?? this.replyTarget),
      replyTargetSenderName: clearReplyTarget
          ? null
          : (replyTargetSenderName ?? this.replyTargetSenderName),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSendState &&
          runtimeType == other.runtimeType &&
          isSending == other.isSending &&
          error == other.error &&
          replyTarget == other.replyTarget &&
          replyTargetSenderName == other.replyTargetSenderName;

  @override
  int get hashCode => Object.hash(
        isSending,
        error,
        replyTarget,
        replyTargetSenderName,
      );
}
