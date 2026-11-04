import 'dart:async';
import 'package:flutter/material.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';

/// Handles ONLY:
/// - Local reactive message stream from [MessagesStore]
/// - Message diffing & AnimatedList coordination
/// - WhatsApp-style chronological sorting
///
/// NO direct network merging, NO UI rendering, NO typing, NO presence
class ChatStreamController {
  final String chatId;
  final String currentUserId;
  final MessagesRepository repo;
  final OutboxService outbox;
  final MessagesStore? messagesStore;

  /// AnimatedList key (used by ChatScreen)
  final GlobalKey<AnimatedListState> listKey = GlobalKey();

  /// Internal message list (source of truth)
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Public stream for UI
  final _controller = StreamController<List<ChatMessage>>.broadcast();
  Stream<List<ChatMessage>> get stream => _controller.stream;

  StreamSubscription<List<ChatMessage>>? _sub;

  ChatStreamController({
    required this.chatId,
    required this.currentUserId,
    required this.repo,
    required this.outbox,
    MessagesStore? messagesStore,
  }) : messagesStore = messagesStore ?? repo.messagesStore {
    _bind();
  }

  // ------------------------------------------------------------
  // STREAM BINDING (Hive-First Single Source of Truth)
  // ------------------------------------------------------------

  void _bind() {
    final stream =
        (messagesStore ?? repo.messagesStore)?.watchMessages(chatId) ??
        outbox.watchForChat(chatId);

    _sub = stream.listen(
      (rawList) {
        final mapped =
            rawList
                .map((m) => m.copyWith(isIncoming: m.senderId != currentUserId))
                .toList()
              ..sort(_messageSort);

        _applyDiff(mapped);
      },
      onError: (err) {
        debugPrint('[ChatStreamController] stream notice: $err');
      },
    );
  }

  // ------------------------------------------------------------
  // DIFFING LOGIC (AnimatedList-safe)
  // ------------------------------------------------------------

  void _applyDiff(List<ChatMessage> newList) {
    // ✅ FIRST SNAPSHOT → loading finished, even if empty
    if (_messages.isEmpty) {
      _messages.addAll(newList);
      _controller.add(_messages);
      return;
    }

    // 🔥 Remove deleted messages
    for (int i = _messages.length - 1; i >= 0; i--) {
      final old = _messages[i];
      if (!newList.any((m) => m.id == old.id)) {
        _messages.removeAt(i);
        listKey.currentState?.removeItem(
          i,
          (context, animation) =>
              SizeTransition(sizeFactor: animation, child: const SizedBox()),
          duration: const Duration(milliseconds: 160),
        );
      }
    }

    // 🔥 Insert / update / move
    for (int newIndex = 0; newIndex < newList.length; newIndex++) {
      final msg = newList[newIndex];
      final oldIndex = _messages.indexWhere((m) => m.id == msg.id);

      if (oldIndex == -1) {
        _messages.insert(newIndex, msg);
        listKey.currentState?.insertItem(newIndex);
      } else if (oldIndex != newIndex) {
        final moved = _messages.removeAt(oldIndex);
        _messages.insert(newIndex, moved);
      } else {
        _messages[newIndex] = msg;
      }
    }

    _controller.add(_messages);
  }

  // ------------------------------------------------------------
  // SORT RULES (WhatsApp-style)
  // ------------------------------------------------------------

  int _messageSort(ChatMessage a, ChatMessage b) {
    // Pending messages always last
    if (a.deliveryState == DeliveryState.sending &&
        b.deliveryState != DeliveryState.sending) {
      return 1;
    }
    if (b.deliveryState == DeliveryState.sending &&
        a.deliveryState != DeliveryState.sending) {
      return -1;
    }

    return a.sentAt.compareTo(b.sentAt);
  }

  // ------------------------------------------------------------
  // CLEANUP
  // ------------------------------------------------------------

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  void prepend(List<ChatMessage> older) {
    if (older.isEmpty) return;

    _messages.insertAll(0, older);
    _controller.add(List.unmodifiable(_messages));
  }
}
