import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';

@Deprecated('Superseded by MessagesStore and ChatsStore in Phase 5.5')
class MessageCache {
  final Box<ChatMessage> _msgBox;
  final Box? _summaryBox;
  final ChatsStore? _chatsStore;
  final int limit;

  MessageCache._(
    this._msgBox,
    this._summaryBox,
    this.limit, [
    this._chatsStore,
  ]);

  factory MessageCache.fromBoxes(
    Box<ChatMessage> msgBox, [
    Box? summaryBox,
    int limit = 200,
    ChatsStore? chatsStore,
  ]) {
    return MessageCache._(msgBox, summaryBox, limit, chatsStore);
  }

  static Future<MessageCache> open({
    required String uid,
    int limit = 200,
    ChatsStore? chatsStore,
  }) async {
    final msgBox = await Hive.openBox<ChatMessage>('cache_msgs_$uid');
    final summaryBox = await Hive.openBox('chat_cache');
    return MessageCache._(msgBox, summaryBox, limit, chatsStore);
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
    if (_chatsStore != null) {
      try {
        await _chatsStore.saveChatSummaries(chats);
      } catch (e) {
        debugPrint('[MessageCache] Non-fatal chatsStore save error: $e');
      }
    }
    if (_summaryBox != null && _summaryBox.isOpen) {
      await _summaryBox.put('summaries', chats.map((c) => c.toJson()).toList());
    }
  }

  // Get cached chat summaries on app startup
  Future<List<ChatSummary>> getCachedChatSummaries() async {
    if (_chatsStore != null) {
      try {
        final list = _chatsStore.getAllChatSummaries();
        if (list.isNotEmpty) return list;
      } catch (e) {
        debugPrint('[MessageCache] Non-fatal chatsStore read error: $e');
      }
    }
    if (_summaryBox != null && _summaryBox.isOpen) {
      final raw = _summaryBox.get('summaries', defaultValue: []);
      return (raw as List)
          .map((e) => ChatSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
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

      if (_summaryBox != null && _summaryBox.isOpen) {
        await _summaryBox.deleteAll(keysToRemove);
      }

      if (keysToRemove.isNotEmpty) {
        debugPrint(
          '[MessageCache] Removed stale chat summaries: $keysToRemove',
        );
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
    if (_chatsStore != null) {
      await _chatsStore.deleteChatSummary(chatId);
    }
    if (_summaryBox != null && _summaryBox.isOpen) {
      final raw = _summaryBox.get('summaries', defaultValue: []);
      if (raw is List) {
        final summaries = raw
            .map((e) => ChatSummary.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        final updated = summaries.where((s) => s.id != chatId).toList();

        await _summaryBox.put('summaries', updated.map((c) => c.toJson()).toList());
      }
    }

    debugPrint('[MessageCache] invalidated chat summary: $chatId');
  }

  // Used by ChatTimelineNotifier.build()
  List<ChatMessage> getCachedMessages(String chatId) {
    return _msgBox.values.where((m) => m.chatId == chatId).toList()
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
