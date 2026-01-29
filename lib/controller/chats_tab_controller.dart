import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:instant_messenger/models/chat_summary.dart';
import 'package:instant_messenger/services/chats_repository.dart';
import 'package:instant_messenger/services/message_cache.dart';

class ChatsTabController extends ChangeNotifier {
  final ChatsRepository _repo;
  final MessageCache _cache;
  bool _disposed = false;


bool _isBound = false;
bool get isBound => _isBound;


final GlobalKey<AnimatedListState> listKey =
    GlobalKey<AnimatedListState>();

List<ChatSummary> _chats = [];
List<ChatSummary> get chats => _chats;

bool _ready = false;
bool get isReady => _ready;

bool _postFrameRequested = false;

int get totalUnread {
  return _chats.fold<int>(
    0,
    (sum, chat) => sum + chat.unread,
  );
}


StreamSubscription<List<ChatSummary>>? _sub;


  ChatsTabController(this._repo, this._cache);

  @override
  void dispose() {
    _sub?.cancel();
    _isBound = false;
    _disposed = true;
    super.dispose();
  }

void ensureBound(String uid) {
  if (_isBound || _postFrameRequested || uid.isEmpty) return;
  _postFrameRequested = true;
  unawaited(bind(uid));
}


  /// Deletes chat summaries for current user, given list of chatIds.
  Future<void> deleteSelectedChats(List<String> chatIds) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      debugPrint('[deleteSelectedChats] ERROR: No current user ID');
      return;
    }

    try {
      for (final chatId in chatIds) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('chats')
            .doc(chatId)
            .delete();
      }
      debugPrint('[deleteSelectedChats] Deleted chats: $chatIds');

      if (!_disposed) {
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('[deleteSelectedChats][ERROR] $e');
      debugPrintStack(stackTrace: st);
      // Optionally rethrow or handle error as needed
    }
  }




Future<void> bind(String uid) async {
  if (_isBound || uid.isEmpty) return;
  _isBound = true;

  // 1️⃣ LOAD FROM HIVE FIRST (ONLY SOURCE FOR UI)
  final cached = await _cache.getCachedChatSummaries();
  debugPrint('[ChatsTabController] hive chats=${cached.length}');

  _chats = List.from(cached);

  _ready = true;
  notifyListeners();

  // 2️⃣ ATTACH FIRESTORE IN BACKGROUND
  _sub?.cancel();
  _sub = _repo.watchUserChats().listen(
    (remoteChats) async {
      debugPrint('[ChatsTabController] firestore sync=${remoteChats.length}');

      // write-through cache
      await _cache.saveChatSummaries(remoteChats);

if (listEquals(_chats, remoteChats)) {
  return;
}


      // update UI only if changed
      _applyRemoteDiff(remoteChats);
    },
    onError: (e, st) {
      debugPrint('[ChatsTabController] firestore error: $e');
      // ❌ DO NOTHING TO UI
    },
  );
}

void _applyRemoteDiff(List<ChatSummary> newList) {
  // FIRST LOAD AFTER EMPTY
 if (_chats.isEmpty && newList.isNotEmpty) {
  _chats = List.from(newList);
  notifyListeners();
  return;
}



  // REMOVE deleted
  for (int i = _chats.length - 1; i >= 0; i--) {
    final old = _chats[i];
    if (!newList.any((c) => c.id == old.id)) {
      _chats.removeAt(i);
      listKey.currentState?.removeItem(
        i,
        (context, animation) =>
            SizeTransition(sizeFactor: animation, child: const SizedBox()),
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  // INSERT / UPDATE / REORDER
  for (int newIndex = 0; newIndex < newList.length; newIndex++) {
    final chat = newList[newIndex];
    final oldIndex = _chats.indexWhere((c) => c.id == chat.id);

    if (oldIndex == -1) {
      _chats.insert(newIndex, chat);
      listKey.currentState?.insertItem(newIndex);
    } else if (oldIndex != newIndex) {
      final moved = _chats.removeAt(oldIndex);
      _chats.insert(newIndex, moved);
    } else {
      _chats[newIndex] = chat;
    }
  }

  notifyListeners();
}




  
}
