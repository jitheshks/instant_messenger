import 'package:hive/hive.dart';
import '../models/chat_message.dart';
import '../models/chat_summary.dart';

class MessageCache {
  final Box<ChatMessage> _msgBox;
  final Box _summaryBox;
  final int limit;

  MessageCache._(this._msgBox, this._summaryBox, this.limit);

  static Future<MessageCache> open({
    required String uid,
    int limit = 200,
  }) async {
    final msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$uid');
    final summaryBox = await Hive.openBox('chat_cache');
    return MessageCache._(msgBox, summaryBox, limit);
  }

  // Save messages batch to cache, enforce per-chat limit
  Future<void> writeThrough(String chatId, List<ChatMessage> msgs) async {
    for (final m in msgs) {
      await _msgBox.put(m.id, m);
    }
    final all = _msgBox.values.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    if (all.length > limit) {
      final remove = all.skip(limit);
      for (final m in remove) {
        await _msgBox.delete(m.id);
      }
    }
  }

  List<ChatMessage> getRecent(String chatId) {
    return _msgBox.values.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  Stream<List<ChatMessage>> watchRecent(String chatId) {
    return _msgBox.watch().map((_) => getRecent(chatId));
  }

  // Save chat summaries list to cache
  Future<void> saveChatSummaries(List<ChatSummary> chats) async {
    await _summaryBox.put('summaries', chats.map((c) => c.toJson()).toList());
  }

  // Get cached chat summaries on app startup
  Future<List<ChatSummary>> getCachedChatSummaries() async {
    final raw = _summaryBox.get('summaries', defaultValue: []);
    return (raw as List)
        .map((e) => ChatSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Remove chat summaries that do not have corresponding cached messages
  Future<void> cleanStaleChatSummaries() async {
    final validChatIds = _msgBox.values.map((m) => m.chatId).toSet();

    final allChatSummaries = await getCachedChatSummaries();

    final staleSummaries = allChatSummaries.where(
      (s) => !validChatIds.contains(s.id),
    );

    if (staleSummaries.isNotEmpty) {
      final keysToRemove = staleSummaries.map((s) => s.id).toList();

      await _summaryBox.deleteAll(keysToRemove);

      if (keysToRemove.isNotEmpty) {
        print('[MessageCache] Removed stale chat summaries: $keysToRemove');
      }
    }
  }

  /// Clear all cached messages in a chat but keep the chat summary tile with cleared preview/unread/time
  Future<void> clearChatMessagesKeepTile(String chatId) async {
    final msgsToRemove = _msgBox.values
        .where((m) => m.chatId == chatId)
        .map((m) => m.id)
        .toList();
    await _msgBox.deleteAll(msgsToRemove);

    final allSummaries = await getCachedChatSummaries();
    final updatedSummaries = allSummaries.map((s) {
      if (s.id == chatId) {
        return s.copyWith(
          lastMessage: '',
          unread: 0,
          muted: false,
          lastTime: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
      return s;
    }).toList();

    await saveChatSummaries(updatedSummaries);
  }


  /// 🔥 Invalidate a single chat summary so ChatsTab reloads fresh data
Future<void> invalidateChatSummary(String chatId) async {
  final raw = _summaryBox.get('summaries', defaultValue: []);
  if (raw is! List) return;

  final summaries = raw
      .map((e) => ChatSummary.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  final updated = summaries.where((s) => s.id != chatId).toList();

  await _summaryBox.put(
    'summaries',
    updated.map((c) => c.toJson()).toList(),
  );

  print('[MessageCache] invalidated chat summary: $chatId');
}


// 🔥 Used by ChatScreenController.ensureInit()
List<ChatMessage> getCachedMessages(String chatId) {
  return _msgBox.values
      .where((m) => m.chatId == chatId)
      .toList()
    ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
}

// 🔥 Used by pagination (older messages)
Future<void> prependMessages(List<ChatMessage> msgs) async {
  for (final m in msgs) {
    await _msgBox.put(m.id, m);
  }
}


// 🔥 Sync Firestore delivery/read state back into Hive cache
Future<void> mergeFromRemote(List<ChatMessage> remoteMessages) async {
  if (remoteMessages.isEmpty) return;

  for (final remote in remoteMessages) {
    final local = _msgBox.get(remote.id);

    if (local == null) continue;

    // Only promote forward (never regress)
    final shouldUpdate =
        remote.deliveryState.index > local.deliveryState.index ||
        remote.failure != local.failure;

    if (!shouldUpdate) continue;

    await _msgBox.put(
      remote.id,
      local.copyWith(
        deliveryState: remote.deliveryState,
        failure: remote.failure,
      ),
    );
  }
}


}
