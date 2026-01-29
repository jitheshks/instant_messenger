import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:instant_messenger/services/message_cache.dart';

import '../models/chat_message.dart';
import 'outbox_meta.dart';
import 'background_upload_scheduler.dart';

/// OutboxService
/// ----------------------------
/// Responsibilities:
/// - Store optimistic messages (Hive)
/// - Store retry metadata
/// - Enqueue background uploads (WorkManager)
///
/// DOES NOT:
/// - Upload media
/// - Talk to Cloudinary
/// - Run background loops
/// - Manage workers
class OutboxService {
  final String cloudName;
  final String uploadPreset;

  final Box<ChatMessage> _msgBox;
  final Box _metaBox;

  // 🔥 SINGLE cache reference (correct)
  final MessageCache _messageCache;

  static const int _maxAutoRetries = 3;

  OutboxService({
    required Box<ChatMessage> messageBox,
    required Box metaBox,
    required this.cloudName,
    required this.uploadPreset,
    required MessageCache messageCache,
  })  : _msgBox = messageBox,
        _metaBox = metaBox,
        _messageCache = messageCache;

  /// 🔥 Expose cache safely (Hive-first reads)
  MessageCache get messageCache => _messageCache;

  // ------------------------------------------------------------
  // WATCH (UI STREAM)
  // ------------------------------------------------------------

  Stream<List<ChatMessage>> watchForChat(String chatId) async* {
    yield _allForChat(chatId);
    yield* _msgBox.watch().map((_) => _allForChat(chatId));
  }

  List<ChatMessage> _allForChat(String chatId) {
    final list = _msgBox.values
        .where((m) => m.chatId == chatId)
        .toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return list;
  }

  // ------------------------------------------------------------
  // SAVE PENDING MESSAGE (ENTRY POINT)
  // ------------------------------------------------------------

Future<void> savePending(ChatMessage msg) async {
  // 1️⃣ Save locally FIRST (instant UI)
  await _msgBox.put(
    msg.id,
    msg.copyWith(
      deliveryState: DeliveryState.sending,
      failure: null,
    ),
  );

  // 2️⃣ Save retry metadata
  await _metaBox.put(
    msg.id,
    OutboxMeta(
      messageId: msg.id,
      chatId: msg.chatId,
      filePath: msg.media!.url,
      mediaKind: msg.media!.kind,
      retryCount: 0,
      nextAttemptAt: DateTime.now(),
    ).toMap(),
  );

  // 3️⃣ Firestore write (async, non-blocking)
  FirebaseFirestore.instance
      .collection('chats')
      .doc(msg.chatId)
      .collection('messages')
      .doc(msg.id)
      .set(msg.toFirestore())
      .then((_) {
        _msgBox.put(
          msg.id,
          msg.copyWith(deliveryState: DeliveryState.sent),
        );
      })
      .catchError((_) {
        _msgBox.put(
          msg.id,
          msg.copyWith(
            failure: MessageFailureReason.firestoreFailed,
          ),
        );
      });

  // 4️⃣ Enqueue background upload
  await BackgroundUploadScheduler.enqueueUpload(
    msg: msg,
    chatId: msg.chatId,
    cloudName: cloudName,
    uploadPreset: uploadPreset,
  );
}


  // ------------------------------------------------------------
  // UI ACTIONS
  // ------------------------------------------------------------

Future<void> retryMessage(String messageId) async {
  final meta = _readMeta(messageId);
  if (meta == null || meta.retryCount >= _maxAutoRetries) return;

  // 🔥 CLEAR FAILURE STATE + RESET TO SENDING
  final msg = _msgBox.get(messageId);
  if (msg != null) {
    await _msgBox.put(
      messageId,
      msg.copyWith(
        failure: null,
        deliveryState: DeliveryState.sending,
      ),
    );
  }

  // 🔁 Reset retry metadata
  await _metaBox.put(
    messageId,
    meta.copyWith(
      retryCount: 0,
      nextAttemptAt: DateTime.now(),
    ).toMap(),
  );

  // 🚀 Re-enqueue upload
  if (msg != null) {
    await BackgroundUploadScheduler.enqueueUpload(
      msg: msg,
      chatId: msg.chatId,
      cloudName: cloudName,
      uploadPreset: uploadPreset,
    );
  }
}


  Future<void> cancelMessage(String messageId) async {
    await _metaBox.delete(messageId);

    final msg = _msgBox.get(messageId);
    if (msg != null) {
      await _msgBox.put(
        messageId,
    msg.copyWith(
  failure: MessageFailureReason.uploadFailed,
  uploadProgress: null,
),

      );
    }

    await BackgroundUploadScheduler.cancelUpload(messageId);
  }

 Future<List<ChatMessage>> getPendingUploads() async {
  return _msgBox.values
      .where(
        (m) =>
            m.type == MessageType.media &&
            m.deliveryState == DeliveryState.sending &&
            m.failure == null, 
      )
      .toList();
}


  // ------------------------------------------------------------
  // INTERNAL
  // ------------------------------------------------------------

  OutboxMeta? _readMeta(String messageId) {
    final raw = _metaBox.get(messageId);
    if (raw is Map) return OutboxMeta.fromMap(raw);
    return null;
  }

  // ------------------------------------------------------------
  // AVATAR UPLOAD (USER / GROUP)
  // ------------------------------------------------------------

  Future<void> enqueueAvatarUpload({
    required String ownerType, // 'user' | 'group'
    required String ownerId,
    required String filePath,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[Outbox] enqueue avatar upload ownerType=$ownerType ownerId=$ownerId',
      );
    }

    await BackgroundUploadScheduler.enqueueAvatarUpload(
      ownerType: ownerType,
      ownerId: ownerId,
      filePath: filePath,
      cloudName: cloudName,
      uploadPreset: uploadPreset,
    );
  }
}
