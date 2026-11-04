import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/chat_scroll_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/chat_send_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/chat_timeline_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/chat_typing_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_state.dart';

export 'package:instant_messenger/features/messaging/presentation/providers/chat_send_notifier.dart';
export 'package:instant_messenger/features/messaging/presentation/providers/chat_timeline_notifier.dart';
export 'package:instant_messenger/features/messaging/presentation/providers/chat_typing_notifier.dart';
export 'package:instant_messenger/features/messaging/presentation/providers/chat_presence_provider.dart';
export 'package:instant_messenger/features/messaging/presentation/providers/messaging_state.dart';

/// Provider for the active session's [MessagesRepository].
final messagesRepositoryProvider = Provider<MessagesRepository?>((ref) {
  return ref.watch(appBootstrapResultProvider).value?.repo;
});

/// Provider for the active session's [MessageCache].
final messageCacheProvider = Provider<MessageCache?>((ref) {
  return ref.watch(appBootstrapResultProvider).value?.cache;
});

/// Arguments passed to chat scoped notifiers and providers.
class ChatControllerArgs {
  final String chatId;
  final String currentUserId;
  final String otherUserId;
  final bool isGroup;

  const ChatControllerArgs({
    required this.chatId,
    required this.currentUserId,
    required this.otherUserId,
    this.isGroup = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatControllerArgs &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          currentUserId == other.currentUserId &&
          otherUserId == other.otherUserId &&
          isGroup == other.isGroup;

  @override
  int get hashCode => Object.hash(chatId, currentUserId, otherUserId, isGroup);
}

/// Provider for the reactive message timeline and pagination.
final chatTimelineNotifierProvider = NotifierProvider.autoDispose
    .family<ChatTimelineNotifier, ChatTimelineState, ChatControllerArgs>(
      (arg) => ChatTimelineNotifier(arg),
    );

/// Provider for text and media message dispatch.
final chatSendNotifierProvider = NotifierProvider.autoDispose
    .family<ChatSendNotifier, ChatSendState, ChatControllerArgs>(
      (arg) => ChatSendNotifier(arg),
    );

/// Provider for realtime typing indicators.
final chatTypingNotifierProvider = NotifierProvider.autoDispose
    .family<ChatTypingNotifier, bool, ChatControllerArgs>(
      (arg) => ChatTypingNotifier(arg),
    );

/// Provider for scroll offset and pagination trigger in chat timeline.
final chatScrollControllerProvider =
    NotifierProvider.autoDispose<ChatScrollNotifier, ChatScrollState>(
      ChatScrollNotifier.new,
    );

/// Provider for message selection in chat timeline.
final chatScreenSelectionControllerProvider =
    NotifierProvider.autoDispose<ChatScreenSelectionNotifier, Set<String>>(
      ChatScreenSelectionNotifier.new,
    );
