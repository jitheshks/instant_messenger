import 'dart:async';
import 'package:hive/hive.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Manages message persistence and timeline queries using Hive CE.
///
/// Operates on the account-scoped `cache_msgs_$uid` box, guaranteeing full
/// compatibility with [MessageCache] while providing reactive timeline streams.
class MessagesStore {
  final Box<ChatMessage> _box;

  MessagesStore(this._box);

  Box<ChatMessage> get box => _box;

  Future<void> saveMessage(ChatMessage message) async {
    final existing = _box.get(message.id);
    if (existing != null) {
      await _box.put(message.id, _mergeMessages(existing, message));
    } else {
      await _box.put(message.id, message);
    }
  }

  Future<void> saveMessages(List<ChatMessage> messages) async {
    final map = <String, ChatMessage>{};
    for (final m in messages) {
      final existing = _box.get(m.id);
      map[m.id] = existing != null ? _mergeMessages(existing, m) : m;
    }
    await _box.putAll(map);
  }

  ChatMessage? getMessage(String id) => _box.get(id);

  List<ChatMessage> getMessagesForChat(String chatId, {int? limit = 50}) {
    final list = _box.values.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    if (limit != null && limit > 0 && list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }

  /// Reactive stream emitting the conversation message timeline.
  Stream<List<ChatMessage>> watchMessages(
    String chatId, {
    int? limit = 50,
  }) async* {
    yield getMessagesForChat(chatId, limit: limit);
    yield* _box.watch().map((_) => getMessagesForChat(chatId, limit: limit));
  }

  /// Updates message delivery state with strict monotonic progression.
  ///
  /// Guarantees:
  /// 1. Delivery states can only advance forward (`sending` -> `sent` -> `delivered` -> `read`).
  ///    A lagging `sent` update will never downgrade a message already marked `delivered` or `read`.
  /// 2. Once a message has been confirmed on the server (`sent` or higher), delayed outbox
  ///    failures cannot overwrite it with a failure state.
  /// 3. Clearing or setting failure is permitted when the message is still in `sending` state.
  Future<void> updateDelivery(
    String id,
    DeliveryState state, {
    MessageFailureReason? failure,
  }) async {
    final existing = _box.get(id);
    if (existing == null) return;

    // Rule 1: A message already confirmed (sent, delivered, read) cannot be marked failed
    // by lagging outbox or retry errors.
    if (existing.deliveryState.index >= DeliveryState.sent.index &&
        failure != null) {
      return;
    }

    // Rule 2: Monotonic progression: delivery state can only advance forward.
    final canAdvanceState = state.index > existing.deliveryState.index;
    final isSameState = state.index == existing.deliveryState.index;
    final isFailureChange = existing.failure != failure;

    if (!canAdvanceState && (!isSameState || !isFailureChange)) {
      // Redundant or regressive update -> ignore to preserve monotonic progress
      return;
    }

    final resolvedState = canAdvanceState ? state : existing.deliveryState;
    // When state reaches sent or higher, clear any failure
    final resolvedFailure = resolvedState.index >= DeliveryState.sent.index
        ? null
        : failure;

    final updated = existing.copyWith(
      deliveryState: resolvedState,
      failure: resolvedFailure,
    );
    await _box.put(id, updated);
  }

  static ChatMessage _mergeMessages(ChatMessage local, ChatMessage incoming) {
    // Monotonic progression: never downgrade delivery state
    final bestState = incoming.deliveryState.index > local.deliveryState.index
        ? incoming.deliveryState
        : local.deliveryState;

    final bestFailure = bestState.index >= DeliveryState.sent.index
        ? null
        : (incoming.failure ?? local.failure);

    return local.copyWith(
      chatId: incoming.chatId.isNotEmpty ? incoming.chatId : local.chatId,
      senderId: incoming.senderId.isNotEmpty
          ? incoming.senderId
          : local.senderId,
      text: incoming.text.isNotEmpty ? incoming.text : local.text,
      sentAt: incoming.sentAt.millisecondsSinceEpoch > 0
          ? incoming.sentAt
          : local.sentAt,
      type: incoming.type,
      media: incoming.media ?? local.media,
      deliveryState: bestState,
      failure: bestFailure,
      isIncoming: incoming.isIncoming,
    );
  }

  Future<void> deleteMessage(String id) async {
    await _box.delete(id);
  }

  Future<void> clearChatMessages(String chatId) async {
    final keys = _box.values
        .where((m) => m.chatId == chatId)
        .map((m) => m.id)
        .toList();
    await _box.deleteAll(keys);
  }
}
