import 'dart:async';
import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/services/chat_repository.dart';
import 'package:instant_messenger/services/outbox_service.dart';

/// Handles ONLY:
/// - Firestore stream
/// - Outbox stream (optimistic messages)
/// - Merge + diffing
/// - AnimatedList coordination
///
/// NO UI, NO uploads, NO typing, NO presence
class ChatStreamController {
  final String chatId;
  final String currentUserId;
  final ChatRepository repo;
  final OutboxService outbox;

  /// AnimatedList key (used by ChatScreen)
  final GlobalKey<AnimatedListState> listKey = GlobalKey();

  /// Internal message list (source of truth)
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Public stream for UI
  final _controller = StreamController<List<ChatMessage>>.broadcast();
  Stream<List<ChatMessage>> get stream => _controller.stream;

  StreamSubscription<void>? _sub;

  ChatStreamController({
    required this.chatId,
    required this.currentUserId,
    required this.repo,
    required this.outbox,
  }) {
    _bind();
  }

  // ------------------------------------------------------------
  // STREAM BINDING
  // ------------------------------------------------------------

  void _bind() {
    List<ChatMessage> latestRemote = [];
    List<ChatMessage> latestLocal = [];

    final remoteStream = repo.watchChat(chatId).map((msgs) {
      latestRemote = msgs
          .map(
            (m) => m.copyWith(
              isIncoming: m.senderId != currentUserId,
            ),
          )
          .toList();
      return null;
    });

    final localStream = outbox.watchForChat(chatId).map((msgs) {
      latestLocal = msgs;
      return null;
    });

    _sub = StreamGroup.merge([remoteStream, localStream]).listen((_) {
      final merged = <String, ChatMessage>{};

      // 1️⃣ Optimistic / local messages (outbox)
      for (final m in latestLocal) {
        merged[m.id] = m;
      }

      // 2️⃣ Firestore messages override local if same ID
      for (final m in latestRemote) {
        merged[m.id] = m;
      }

      final newList = merged.values.toList()
        ..sort(_messageSort);
// 🔥 Sync Firestore delivery/read back into Hive
outbox.messageCache.mergeFromRemote(newList);

      _applyDiff(newList);
    });
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
