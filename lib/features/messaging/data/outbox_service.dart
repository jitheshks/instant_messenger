import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/outbox_meta.dart';
import 'package:instant_messenger/features/media/data/background_upload_scheduler.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';

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

  // Optional legacy cache reference
  final MessageCache? _messageCache;
  ChatsStore? _chatsStore;

  final SupabaseClient? _supabaseClient;
  final Set<String> _activeSending = {};

  static const int _maxAutoRetries = 3;

  OutboxService({
    required Box<ChatMessage> messageBox,
    required Box metaBox,
    this.cloudName = '',
    this.uploadPreset = '',
    MessageCache? messageCache,
    SupabaseClient? supabaseClient,
    ChatsStore? chatsStore,
  }) : _msgBox = messageBox,
       _metaBox = metaBox,
       _messageCache = messageCache,
       _supabaseClient = supabaseClient,
       _chatsStore = chatsStore;

  /// Attaches or updates the active [ChatsStore].
  void attachChatsStore(ChatsStore store) {
    _chatsStore = store;
  }

  ChatsStore? get chatsStore => _chatsStore;

  SupabaseClient get _sb => _supabaseClient ?? Supabase.instance.client;

  SupabaseClient? get _safeSb {
    if (_supabaseClient != null) return _supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Expose cache safely (Hive-first reads)
  @Deprecated('Use MessagesStore and ChatsStore directly')
  MessageCache get messageCache =>
      _messageCache ??
      MessageCache.fromBoxes(
        _msgBox,
        null,
      );

  /// Whether a message insert is currently in flight.
  bool isSending(String messageId) => _activeSending.contains(messageId);

  // ------------------------------------------------------------
  // WATCH (UI STREAM)
  // ------------------------------------------------------------

  Stream<List<ChatMessage>> watchForChat(String chatId) async* {
    yield _allForChat(chatId);
    yield* _msgBox.watch().map((_) => _allForChat(chatId));
  }

  List<ChatMessage> _allForChat(String chatId) {
    final list = _msgBox.values.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return list;
  }

  // ------------------------------------------------------------
  // SAVE PENDING MESSAGE (ENTRY POINT)
  // ------------------------------------------------------------

  Future<void> savePending(
    ChatMessage msg, {
    String? otherUserId,
    String? otherAvatar,
  }) async {
    // 1️⃣ Save locally FIRST (instant UI)
    await _msgBox.put(
      msg.id,
      msg.copyWith(deliveryState: DeliveryState.sending, failure: null),
    );

    // Optimistically update conversation preview in ChatsStore
    if (_chatsStore != null) {
      try {
        final sender = msg.senderId.isNotEmpty
            ? msg.senderId
            : (_safeSb?.auth.currentUser?.id ?? '');
        await _chatsStore!.updateOptimisticPreview(
          chatId: msg.chatId,
          message: msg,
          currentUserId: sender,
          otherUserId: otherUserId,
          otherAvatar: otherAvatar,
        );
      } catch (e) {
        debugPrint(
          '[OutboxService] Non-fatal chat summary optimistic update notice: $e',
        );
      }
    }

    // 2️⃣ Save retry metadata if media attachment present
    if (msg.media != null) {
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
    }

    // 3️⃣ Remote write to Supabase (async, non-blocking)
    unawaited(_insertToSupabase(msg));

    // 4️⃣ Enqueue background upload
    if (msg.type == MessageType.media && msg.media != null) {
      await BackgroundUploadScheduler.enqueueUpload(
        msg: msg,
        chatId: msg.chatId,
        cloudName: cloudName,
        uploadPreset: uploadPreset,
      );
    }
  }

  @visibleForTesting
  Future<void> insertToSupabase(ChatMessage msg) => _insertToSupabase(msg);

  Future<void> _insertToSupabase(ChatMessage msg) async {
    if (!_activeSending.add(msg.id)) {
      debugPrint(
        '[OutboxService] Insert skipped: message ${msg.id} is already in-flight.',
      );
      return;
    }

    try {
      final client = _safeSb;
      if (client == null) {
        debugPrint(
          '[OutboxService] Supabase client not initialized; skipping remote insert.',
        );
        return;
      }

      final sender = client.auth.currentUser?.id ?? msg.senderId;

      final payload = <String, dynamic>{
        'id': msg.id,
        'chat_id': msg.chatId,
        'sender_id': sender,
        'type': msg.type.name,
        'text': msg.text,
        if (msg.media != null) 'media': msg.media!.toMap(),
        'status': 1, // sent
        'sent_at': msg.sentAt.toUtc().toIso8601String(),
        'is_forwarded': msg.isForwarded,
        if (msg.replyToMessageId != null) 'reply_to_message_id': msg.replyToMessageId,
        if (msg.hasReply)
          'reply_snapshot': {
            if (msg.replyText != null) 'text': msg.replyText,
            if (msg.replySenderName != null) 'sender_name': msg.replySenderName,
            if (msg.replyMediaKind != null) 'media_kind': msg.replyMediaKind,
          },
      };

      try {
        await _sb.from('messages').insert(payload);
      } on PostgrestException catch (e) {
        // Fallback ONLY when database/schema explicitly lacks forward/reply columns or their grants
        final isMissingColumnError = e.code == 'PGRST204' ||
            e.code == '42703' ||
            (e.code == '42501' &&
                e.message.toLowerCase().contains('column') &&
                (e.message.contains('is_forwarded') ||
                    e.message.contains('reply_to_message_id') ||
                    e.message.contains('reply_snapshot')));

        if (isMissingColumnError) {
          debugPrint(
            '[OutboxService] Schema missing reply/forward columns, falling back to legacy payload: ${e.message}',
          );
          final fallbackPayload = Map<String, dynamic>.from(payload)
            ..remove('is_forwarded')
            ..remove('reply_to_message_id')
            ..remove('reply_snapshot');
          await _sb.from('messages').insert(fallbackPayload);
        } else {
          rethrow;
        }
      }

      // Avoid overwriting if message was cancelled during network await
      final local = _msgBox.get(msg.id);
      if (local != null &&
          local.failure == MessageFailureReason.uploadFailed &&
          _metaBox.get(msg.id) == null) {
        return;
      }

      await _msgBox.put(
        msg.id,
        msg.copyWith(deliveryState: DeliveryState.sent, failure: null),
      );
    } catch (err) {
      debugPrint('[OutboxService] Supabase insert note: $err');

      if (err is PostgrestException && err.code == '23505') {
        try {
          final existing = await _sb
              .from('messages')
              .select('id, chat_id, sender_id')
              .eq('id', msg.id)
              .maybeSingle();

          final currentUserId = _sb.auth.currentUser?.id ?? msg.senderId;
          if (existing != null &&
              existing['sender_id'] == currentUserId &&
              existing['chat_id'] == msg.chatId) {
            debugPrint(
              '[OutboxService] Message ${msg.id} was already confirmed on server (23505 idempotent match).',
            );
            await _msgBox.put(
              msg.id,
              msg.copyWith(deliveryState: DeliveryState.sent, failure: null),
            );
            return;
          }
        } catch (queryErr) {
          debugPrint(
            '[OutboxService] 23505 verification query error: $queryErr',
          );
        }
      }

      // Check if message was cancelled while insert was in flight
      final local = _msgBox.get(msg.id);
      if (local != null &&
          local.failure == MessageFailureReason.uploadFailed &&
          _metaBox.get(msg.id) == null) {
        return;
      }

      final isPermanent =
          err is PostgrestException &&
          (err.code == '42501' || // RLS permission denied
              err.code == '23503' || // FK violation (chat/sender missing)
              err.code == '22P02'); // Invalid syntax/UUID

      await _msgBox.put(
        msg.id,
        msg.copyWith(
          failure: isPermanent
              ? MessageFailureReason.unknown
              : MessageFailureReason.serverFailed,
        ),
      );
    } finally {
      _activeSending.remove(msg.id);
    }
  }

  // ------------------------------------------------------------
  // UI ACTIONS
  // ------------------------------------------------------------

  Future<void> retryMessage(String messageId) async {
    if (_activeSending.contains(messageId)) {
      debugPrint(
        '[OutboxService] Retry skipped: message $messageId is currently in-flight.',
      );
      return;
    }

    final meta = _readMeta(messageId);
    if (meta == null || meta.retryCount >= _maxAutoRetries) return;

    // Reset local failure state to sending
    final msg = _msgBox.get(messageId);
    if (msg != null) {
      await _msgBox.put(
        messageId,
        msg.copyWith(failure: null, deliveryState: DeliveryState.sending),
      );
    }

    // Reset retry metadata
    await _metaBox.put(
      messageId,
      meta.copyWith(retryCount: 0, nextAttemptAt: DateTime.now()).toMap(),
    );

    // Re-enqueue upload & Supabase insert
    if (msg != null) {
      if (msg.type == MessageType.media) {
        await BackgroundUploadScheduler.enqueueUpload(
          msg: msg,
          chatId: msg.chatId,
          cloudName: cloudName,
          uploadPreset: uploadPreset,
        );
      }
      await _insertToSupabase(msg);
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

  String? get currentUserId => _sb.auth.currentUser?.id;

  /// Updates local message upon background upload completion (called from main isolate).
  Future<void> markUploadCompleted({
    required String messageId,
    required String publicUrl,
    String? mimeType,
  }) async {
    final msg = _msgBox.get(messageId);
    if (msg != null) {
      await _msgBox.put(
        messageId,
        msg.copyWith(
          failure: null,
          deliveryState: DeliveryState.sent,
          uploadProgress: null,
          media: msg.media?.copyWith(url: publicUrl, mime: mimeType),
        ),
      );
    }
  }

  /// Updates local message upon background upload failure (called from main isolate).
  Future<void> markUploadFailed({
    required String messageId,
    String? reason,
  }) async {
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
