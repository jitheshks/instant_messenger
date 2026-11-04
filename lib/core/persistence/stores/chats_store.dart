import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/sync/chat_preview_ordering_policy.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Manages conversation summaries and reactive inbox list queries in Hive CE.
class ChatsStore {
  final Box _box;

  ChatsStore(this._box);

  Box get box => _box;

  Future<void> saveChatSummary(ChatSummary summary) async {
    await _box.put(summary.id, summary.toJson());
  }

  Future<void> saveChatSummaries(List<ChatSummary> summaries) async {
    final map = {for (final s in summaries) s.id: s.toJson()};
    await _box.putAll(map);
  }

  ChatSummary? getChatSummary(String chatId) {
    final raw = _box.get(chatId);
    if (raw is Map) {
      return ChatSummary.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  List<ChatSummary> getAllChatSummaries() {
    final summaries = <ChatSummary>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          summaries.add(ChatSummary.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    summaries.sort((a, b) => b.lastTime.compareTo(a.lastTime));
    return summaries;
  }

  /// Reactive stream of conversation summaries for the inbox.
  Stream<List<ChatSummary>> watchChatSummaries() async* {
    yield getAllChatSummaries();
    yield* _box.watch().map((_) => getAllChatSummaries());
  }

  /// Standardized formatter for conversation previews across text and media kinds.
  static String formatMessagePreview(ChatMessage msg) {
    if (msg.type == MessageType.text) {
      return msg.text.trim();
    }

    if (msg.media != null) {
      final caption = msg.text.trim();
      switch (msg.media!.kind) {
        case MediaKind.image:
          return caption.isNotEmpty ? caption : '📷 Photo';
        case MediaKind.video:
          return caption.isNotEmpty ? caption : '🎥 Video';
        case MediaKind.audio:
          return '🎵 Audio';
        case MediaKind.document:
          return msg.media!.fileName?.isNotEmpty == true
              ? msg.media!.fileName!
              : (caption.isNotEmpty ? caption : '📄 Document');
      }
    }

    if (msg.text.trim().isNotEmpty) {
      return msg.text.trim();
    }

    return '[${msg.type.name}]';
  }

  /// Optimistically updates or creates a conversation preview from an outgoing [message].
  ///
  /// Guarantees:
  /// 1. Timestamp collision protection & tie-breaking: Never overwrites with an older message.
  /// 2. Metadata preservation: Preserves unread counts, muted status, otherPhoneE164, avatar, and members.
  /// 3. Chat summary integrity: Verifies non-empty [chatId] and [otherUserId] before creating new summaries.
  Future<void> updateOptimisticPreview({
    required String chatId,
    required ChatMessage message,
    required String currentUserId,
    String? otherUserId,
    String? otherPhoneE164,
    String? otherAvatar,
  }) async {
    if (chatId.isEmpty) return;

    final existing = getChatSummary(chatId);
    final preview = formatMessagePreview(message);
    final statusInt = message.statusInt;

    if (existing != null) {
      // Safeguard 1: Conservative tie policy via centralized ordering policy
      final action = ChatPreviewOrderingPolicy.evaluate(
        candidateTime: message.sentAt,
        candidateMessageId: message.id,
        existingTime: existing.lastTime,
        existingMessageId: existing.lastMessageId,
      );

      if (action == CandidateAction.ignoreCandidate) {
        return;
      }

      if (action == CandidateAction.updateStatusOnly) {
        if (statusInt > existing.lastMessageStatus) {
          final updated = existing.copyWith(lastMessageStatus: statusInt);
          await saveChatSummary(updated);
        }
        return;
      }

      final updated = existing.copyWith(
        lastMessage: preview,
        lastTime: message.sentAt,
        lastSenderId: message.senderId,
        lastMessageStatus: statusInt,
        lastMessageId: message.id,
      );
      await saveChatSummary(updated);
    } else {
      // Safeguard 4: Chat summary integrity - never construct incomplete summaries
      final peerId = (otherUserId != null && otherUserId.isNotEmpty)
          ? otherUserId
          : '';
      if (peerId.isEmpty || currentUserId.isEmpty) {
        return;
      }

      final newSummary = ChatSummary(
        id: chatId,
        lastMessage: preview,
        lastTime: message.sentAt,
        unread: 0,
        muted: false,
        otherUserId: peerId,
        otherPhoneE164: otherPhoneE164,
        avatarUrl: otherAvatar,
        members: [currentUserId, peerId],
        lastSenderId: currentUserId,
        lastMessageStatus: statusInt,
        lastMessageId: message.id,
      );
      await saveChatSummary(newSummary);
    }
  }

  /// Updates delivery status for [chatId] with strict message-ID ownership and monotonic progression.
  ///
  /// Guarantees:
  /// 1. Ownership: Only updates if [messageId] matches the message currently represented by the preview.
  /// 2. Monotonic progression: Status can only advance (`0 -> 1 -> 2 -> 3`).
  Future<void> updateDeliveryStatus(
    String chatId,
    String messageId,
    int newStatus,
  ) async {
    if (chatId.isEmpty || messageId.isEmpty) return;

    final existing = getChatSummary(chatId);
    if (existing == null) return;

    // Safeguard 2: Delivery status ownership
    if (existing.lastMessageId != null &&
        existing.lastMessageId != messageId) {
      return;
    }

    // Safeguard 3: Monotonic progression
    if (newStatus <= existing.lastMessageStatus) {
      return;
    }

    final updated = existing.copyWith(
      lastMessageStatus: newStatus,
      lastMessageId: existing.lastMessageId ?? messageId,
    );
    await saveChatSummary(updated);
  }

  /// Safeguard 5: Crash consistency recovery.
  ///
  /// Reconciles [ChatsStore] with locally persisted messages in [MessagesStore]
  /// and genuine outbox mutation payloads in [OutboxStore] after unexpected application
  /// termination between outbox and chat store writes.
  Future<void> recoverLatestPreviews(
    MessagesStore messagesStore,
    String currentUserId, {
    OutboxStore? outboxStore,
  }) async {
    if (!box.isOpen || !messagesStore.box.isOpen) return;

    final chatLatestMap = <String, ChatMessage>{};
    for (final msg in messagesStore.box.values) {
      if (msg.chatId.isEmpty) continue;
      final currentLatest = chatLatestMap[msg.chatId];
      if (currentLatest == null || msg.sentAt.isAfter(currentLatest.sentAt)) {
        chatLatestMap[msg.chatId] = msg;
      }
      // If timestamps are identical, conservative tie policy preserves the established message
    }

    for (final entry in chatLatestMap.entries) {
      final chatId = entry.key;
      final latestMsg = entry.value;
      final existing = getChatSummary(chatId);

      if (existing == null) {
        String otherId = '';
        String? otherAvatar;

        if (latestMsg.senderId != currentUserId) {
          // Incoming message: sender is peer
          otherId = latestMsg.senderId;
        } else if (outboxStore != null && outboxStore.box.isOpen) {
          // Outgoing message: look up genuine recipient metadata from OutboxStore mutation payload
          final outboxEntry = outboxStore.getById(latestMsg.id);
          if (outboxEntry != null && outboxEntry.payloadJson.isNotEmpty) {
            try {
              final Map<String, dynamic> data =
                  jsonDecode(outboxEntry.payloadJson);
              final peer = data['otherUserId'] as String?;
              if (peer != null && peer.isNotEmpty) {
                otherId = peer;
                otherAvatar = data['otherAvatar'] as String?;
              }
            } catch (_) {}
          }
        }

        // Only create summary if peer identity is genuinely available (never fabricate)
        if (otherId.isNotEmpty) {
          await updateOptimisticPreview(
            chatId: chatId,
            message: latestMsg,
            currentUserId: currentUserId,
            otherUserId: otherId,
            otherAvatar: otherAvatar,
          );
        }
      } else {
        final action = ChatPreviewOrderingPolicy.evaluate(
          candidateTime: latestMsg.sentAt,
          candidateMessageId: latestMsg.id,
          existingTime: existing.lastTime,
          existingMessageId: existing.lastMessageId,
        );

        if (action == CandidateAction.replacePreview) {
          await updateOptimisticPreview(
            chatId: chatId,
            message: latestMsg,
            currentUserId: currentUserId,
          );
        } else if (action == CandidateAction.updateStatusOnly &&
            latestMsg.statusInt > existing.lastMessageStatus) {
          await updateDeliveryStatus(
            chatId,
            latestMsg.id,
            latestMsg.statusInt,
          );
        }
      }
    }
  }

  Future<void> deleteChatSummary(String chatId) async {
    await _box.delete(chatId);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
