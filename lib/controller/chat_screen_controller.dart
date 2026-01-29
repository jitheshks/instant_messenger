// lib/controller/chat_screen_controller.dart

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:instant_messenger/controller/chat_media_controller.dart';
import 'package:instant_messenger/controller/chat_presence_controller.dart';
import 'package:instant_messenger/controller/chat_scroll_controller.dart';
import 'package:instant_messenger/controller/chat_stream_controller.dart';
import 'package:instant_messenger/controller/chat_typing_controller.dart';

import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/models/user_presence.dart';
import 'package:instant_messenger/services/chat_repository.dart';
import 'package:instant_messenger/services/outbox_service.dart';
import 'package:instant_messenger/controller/chat_send_controller.dart';

/// Callback used to trigger push AFTER Firestore write
typedef OnPushCallback =
    Future<void> Function({
      required String chatId,
      required String senderId,
      required String preview,
      required String type,
      required String messageId,
      List<String>? recipientUserIds,
      List<String>? recipientPlayerIds,
      String? senderName,
      String? avatarUrl,
    });

class ChatScreenController extends ChangeNotifier with WidgetsBindingObserver {
  // ---------------- CORE SERVICES ----------------
  final ChatRepository _repo;
  final OutboxService _outbox;
  late ChatSendController _sender;
  late final ChatMediaController _media;
ChatTypingController? _typing;
ChatPresenceController? _presence;

  late final ChatStreamController _streams;


ChatScrollController? _scrollCtrl;

  Stream<List<ChatMessage>> get stream => _streams.stream;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  StreamSubscription<List<ChatMessage>>? _msgSub;

  // ---------------- CHAT CONTEXT ----------------
  final String chatId;
  final String currentUserId;

  /// Push hook (OneSignal handled outside)
  final OnPushCallback? onPush;

 // ---------------- OTHER USER ----------------
final String otherUserId;        // ✅ REAL FIELD
String get peerId => otherUserId; // optional alias if you want

  late String otherName;

  String? otherAvatar;

  // ---------------- INPUT ----------------
  final TextEditingController input = TextEditingController();
    // ---------------- SCROLL / PAGINATION ----------------
final ScrollController scrollController = ScrollController();
bool _scrollListenerAttached = false;



  // ---------------- STATE ----------------
  bool _initialized = false;
  bool _hasInit = false;
  bool _disposed = false;

  bool initInProgress = false;
  String? initErrorPublic;
  bool get hasText => input.text.trim().isNotEmpty;

  // ---------------- PAGINATION STATE ----------------
  DocumentSnapshot? _lastDoc;
  bool hasMore = true;
  bool loadingMore = false;

 

  ChatScreenController({
    required ChatRepository repo,
    required OutboxService outbox,
    required this.chatId,
    required this.currentUserId,
    this.onPush,
     required this.otherUserId,
  }) : _repo = repo,
       _outbox = outbox {
    _media = ChatMediaController();
    WidgetsBinding.instance.addObserver(this);
  }

  // ---------------- GETTERS ----------------

bool get isReady => _initialized;

  bool get canSend => input.text.trim().isNotEmpty;

  /// ✅ REQUIRED BY ChatScreen UI
  bool get hasInitError => initErrorPublic != null;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

@override
void dispose() {
  _msgSub?.cancel();
  _typing?.dispose();
  scrollController.dispose();
  WidgetsBinding.instance.removeObserver(this);
  _disposed = true;
  input.dispose();
  super.dispose();
}


  void attachScrollListener() {
  if (_scrollListenerAttached) return;
  _scrollListenerAttached = true;

  scrollController.addListener(() {
    // ListView(reverse: true)
    // top == older messages
    if (scrollController.position.pixels <= 120) {
      loadOlder();
    }
  });
}


  // ---------------- UI HELPERS ----------------

  /// ✅ Retry button support
  void clearInitError() {
    initErrorPublic = null;
    notifyListeners();
  }

  /// ✅ ChatInput support
  void onInputChanged(String value) {
    notifyListeners();
  }

  // ---------------- INIT ----------------
Future<void> ensureInit({
  
  required String otherName,
  String? otherAvatar,
  Duration timeout = const Duration(seconds: 6),
}) async {

  debugPrint('[ChatInit] START chatId=$chatId');

if (_disposed || _hasInit) return;

  initInProgress = true;
  initErrorPublic = null;
  notifyListeners();

  try {
    // 🔥 STEP 0: INIT STREAM FIRST (NO IO)
    _streams = ChatStreamController(
      chatId: chatId,
      currentUserId: currentUserId,
      repo: _repo,
      outbox: _outbox,
    );

    // 🔥 STEP 1: LOAD FROM HIVE FIRST (INSTANT UI)
    final cached = _outbox.messageCache.getRecent(chatId);
    if (cached.isNotEmpty) {
      _streams.prepend(cached);
      _messages = List.from(cached);
      _isLoading = false;
    }
    _initialized = true;


notifyListeners();
    // 🔥 STEP 2: ENSURE CHAT DOC (NETWORK)
    await _initInternal(
      otherName: otherName,
      otherAvatar: otherAvatar,
    ).timeout(timeout);



_presence ??= ChatPresenceController();
    // 🔥 STEP 3: INIT OTHER CONTROLLERS
    _typing = ChatTypingController(
      chatId: chatId,
      currentUserId: currentUserId,
    );


    _sender = ChatSendController(
      repo: _repo,
      outbox: _outbox,
      chatId: chatId,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      otherName: otherName,
      otherAvatar: otherAvatar,
      onPush: onPush,
    );

    // 🔥 STEP 4: ATTACH STREAM LAST
    _msgSub = _streams.stream.listen(_onMessagesUpdate);
debugPrint('[ChatInit] MARK READY');


    _hasInit = true;
    initInProgress = false;
    notifyListeners();
  } catch (e) {
    initInProgress = false;
    initErrorPublic = e.toString();
    notifyListeners();
  }
}


  Future<void> _initInternal({
    required String otherName,
    String? otherAvatar,
  }) async {

debugPrint('[ChatInit] _initInternal otherUserId=$otherUserId otherName=$otherName');


    // 🔥 otherUserId MUST already be known (passed via navigation)
    if (otherUserId.isEmpty) {
      throw Exception('Missing otherUserId');
    }

    // Save UI metadata
    this.otherName = otherName;
    this.otherAvatar = otherAvatar;

    // 🔥 Ensure chat document exists (creates if missing)
    await _repo.ensureChatDoc(
      chatId: chatId,
      uidA: currentUserId,
      uidB: otherUserId,
      title: otherName,
      avatarUrl: otherAvatar,
    );
  }

  // ---------------- SEND (DELEGATED) ----------------

  Future<void> sendCurrentText() async {
    final text = input.text;
    if (text.trim().isEmpty) return;

    input.clear();
    notifyListeners();

    await _sender.sendCurrentText(text);
  }

  Future<void> sendImages(List<XFile> files, String caption) =>
      _sender.sendImages(files, caption);

  Future<void> sendAudio(XFile file) => _sender.sendAudio(file);

  Future<void> sendVoice(File file, int durationMs) =>
      _sender.sendVoice(file, durationMs);

  Future<void> sendDocument(XFile file) => _sender.sendDocument(file);

  Future<void> retryMediaMessage(String messageId) =>
      _sender.retryMediaMessage(messageId);

  Future<void> cancelMediaMessage(String messageId) =>
      _sender.cancelMediaMessage(messageId);

  // ---------------- READ RECEIPTS ----------------

 Future<void> maybeMarkRead(ChatMessage newest) async {
  if (!newest.isIncoming) return;
  if (newest.isRead) return;

  await _repo.markRead(chatId, currentUserId);
}

// ---------------- TYPING (SAFE) ----------------

void onTypingChanged(String text) {
  _typing?.onTypingChanged(text);
}

void clearTyping() {
  _typing?.clearTyping();
}

Stream<bool> watchTyping(String otherUserId) {
  return _typing?.watchTyping(otherUserId) ?? const Stream.empty();
}


  // ---------------- PRESENCE (DELEGATED) ----------------

 Stream<UserPresence> watchPresence(String otherUserId) {
  return _presence?.watchPresence(otherUserId)
      ?? const Stream<UserPresence>.empty();
}


bool get presenceReady => _presence?.presenceReady ?? false;

  void startVoiceRecording() {
    debugPrint('[Voice] Start recording');
  }

  void toggleEmojiKeyboard() {
    // for now: just focus/unfocus
    // later: open custom emoji picker
  }

  void openCamera() {
    // camera → preview → send
  }

  // ---------------- MEDIA PICKING (DELEGATED) ----------------

  Future<void> pickFromGallery(String caption) async {
    final files = await _media.pickFromGallery();
    if (files.isEmpty) return;

    await sendImages(files, caption);
  }

  Future<void> pickDocument() async {
    final file = await _media.pickDocument();
    if (file == null) return;

    await sendDocument(file);
  }

  Future<void> pickAudio() async {
    final file = await _media.pickAudio();
    if (file == null) return;

    await sendAudio(file);
  }

  Future<void> pickFromCamera() async {
    final file = await _media.pickFromCamera();
    if (file == null) return;

    // future:
    // await sendImages([XFile(file.path)], '');
  }

  void _onMessagesUpdate(List<ChatMessage> newList) {
  // 🔥 Stop loader on FIRST snapshot only
  if (_isLoading) {
    _isLoading = false;
  }

  // ----------------------------------------
  // 🔥 UNREAD COUNT LOGIC
  // ----------------------------------------
  final oldCount = _messages.length;
  final newCount = newList.length;

  if (newCount > oldCount) {
    final added = newList.sublist(oldCount);

    // Count ONLY incoming & unseen messages
final unreadIncoming = added.where((m) =>
    m.isIncoming && !m.isRead).length;


    if (unreadIncoming > 0) {
      // 🔥 Notify scroll controller
      _scrollCtrl?.onNewMessages(unreadIncoming);
    }
  }

  _messages = List.from(newList);

  // 🔥 Promote incoming messages to DELIVERED (idempotent)
_repo.markDeliveredIfNeeded(
  chatId: chatId,
  currentUserId: currentUserId,
  messages: _messages,
);


  notifyListeners();
}

void bindScrollController(ChatScrollController ctrl) {
  _scrollCtrl = ctrl;
}



Future<void> loadOlder() async {
  // 0️⃣ Guards (VERY IMPORTANT)
  if (!hasMore || loadingMore || _lastDoc == null) return;

  loadingMore = true;
  notifyListeners();

  try {
    // 1️⃣ Fetch older messages from Firestore
    final snap = await _repo.loadOlderMessages(chatId, _lastDoc!);

    // 2️⃣ No more messages
    if (snap.isEmpty) {
      hasMore = false;
      return;
    }

    // 3️⃣ Firestore query is DESC → reverse for UI (old → new)
    final olderMessages = snap.reversed.toList();

    // 4️⃣ 🔥 SAVE TO HIVE FIRST (CRITICAL)
    // This guarantees:
    // - offline pagination
    // - app kill / reopen keeps old messages
    await _outbox.messageCache.prependMessages(olderMessages);

    // 5️⃣ Update pagination cursor
    _lastDoc = snap.last as DocumentSnapshot;

    // 6️⃣ Update in-memory stream (UI)
    _streams.prepend(olderMessages);
  } catch (e, st) {
    debugPrint('[ChatScreen] loadOlder error: $e');
    debugPrintStack(stackTrace: st);
  } finally {
    // 7️⃣ Always reset loading flag
    loadingMore = false;
    notifyListeners();
  }
}

}
