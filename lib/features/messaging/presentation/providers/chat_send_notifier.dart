import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/features/media/data/media_compress_service.dart';
import 'package:instant_messenger/features/media/data/video_thumbnail_service.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/notifications/presentation/providers/notification_providers.dart';
import 'package:uuid/uuid.dart';

class ChatSendNotifier extends Notifier<ChatSendState> {
  final ChatControllerArgs arg;

  ChatSendNotifier(this.arg);

  @override
  ChatSendState build() {
    return const ChatSendState();
  }

  void setReplyTarget(ChatMessage msg, {String? senderName}) {
    state = state.copyWith(
      replyTarget: msg,
      replyTargetSenderName: senderName,
      clearError: true,
    );
  }

  void clearReplyTarget() {
    state = state.copyWith(clearReplyTarget: true);
  }

  Future<void> sendText(
    String text, {
    required String otherName,
    String? otherAvatar,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final repo = ref.read(messagesRepositoryProvider);
    final push = ref.read(pushControllerProvider);
    if (repo == null) return;

    final keepAlive = ref.keepAlive();
    state = state.copyWith(isSending: true, clearError: true);

    try {
      final currentReply = state.replyTarget;
      final currentReplySender = state.replyTargetSenderName;

      final msg = ChatMessage(
        id: const Uuid().v4(),
        chatId: arg.chatId,
        senderId: arg.currentUserId,
        text: trimmed,
        sentAt: DateTime.now().toUtc(),
        type: MessageType.text,
        deliveryState: DeliveryState.sending,
        replyToMessageId: currentReply?.id,
        replyText: currentReply?.text.isNotEmpty == true
            ? currentReply!.text
            : (currentReply?.media != null
                ? '[${currentReply!.media!.kind.name}]'
                : null),
        replySenderName: currentReplySender ??
            (currentReply != null
                ? (currentReply.senderId == arg.currentUserId
                    ? 'You'
                    : otherName)
                : null),
        replyMediaKind: currentReply?.media?.kind.name,
      );

      final serverId = await repo.sendMessage(
        arg.chatId,
        msg,
        otherUserId: arg.otherUserId,
        otherName: otherName,
        otherAvatar: otherAvatar,
      );

      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, clearReplyTarget: true);

      // Asynchronously trigger server-side push notification dispatch
      // without pausing the UI thread or blocking the message input composer
      unawaited(
        push
            .onMessageSent(
              chatId: arg.chatId,
              senderId: arg.currentUserId,
              preview: msg.text,
              type: 'text',
              messageId: serverId,
              recipientUserIds: [arg.otherUserId],
            )
            .catchError((e) {
              debugPrint('[ChatSendNotifier] Push notice warning: $e');
            }),
      );
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(isSending: false, error: e.toString());
      }
    } finally {
      keepAlive.close();
    }
  }

  Future<void> sendImages(
    List<XFile> files,
    String caption, {
    required String otherName,
    String? otherAvatar,
  }) async {
    if (files.isEmpty) return;

    final outbox = ref.read(outboxServiceProvider);
    if (outbox == null) return;

    final keepAlive = ref.keepAlive();
    state = state.copyWith(isSending: true, clearError: true);

    try {
      for (final file in files) {
        if (!ref.mounted) return;
        final msgId = const Uuid().v4();
        final originalFile = File(file.path);
        final isVideo = file.path.toLowerCase().endsWith('.mp4');

        File? thumb;
        if (isVideo) {
          thumb = await VideoThumbnailService.generate(file.path);
        }

        if (!ref.mounted) return;

        final File compressedFile = isVideo
            ? await MediaCompressService.compressVideo(originalFile)
            : await MediaCompressService.compressImage(originalFile);

        if (!ref.mounted) return;

        final currentReply = state.replyTarget;
        final currentReplySender = state.replyTargetSenderName;

        final msg = ChatMessage(
          id: msgId,
          chatId: arg.chatId,
          senderId: arg.currentUserId,
          text: caption,
          sentAt: DateTime.now().toUtc(),
          deliveryState: DeliveryState.sending,
          type: MessageType.media,
          uploadProgress: 0.0,
          failure: null,
          replyToMessageId: currentReply?.id,
          replyText: currentReply?.text.isNotEmpty == true
              ? currentReply!.text
              : (currentReply?.media != null
                  ? '[${currentReply!.media!.kind.name}]'
                  : null),
          replySenderName: currentReplySender ??
              (currentReply != null
                  ? (currentReply.senderId == arg.currentUserId
                      ? 'You'
                      : otherName)
                  : null),
          replyMediaKind: currentReply?.media?.kind.name,
          media: MessageMedia(
            url: compressedFile.path,
            thumbUrl: thumb?.path,
            kind: isVideo ? MediaKind.video : MediaKind.image,
            mime: isVideo ? 'video/mp4' : 'image/*',
            size: compressedFile.lengthSync(),
          ),
        );

        await outbox.savePending(
          msg,
          otherUserId: arg.otherUserId,
          otherAvatar: otherAvatar,
        );
      }

      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, clearReplyTarget: true);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(isSending: false, error: e.toString());
      }
    } finally {
      keepAlive.close();
    }
  }

  Future<void> sendAudio(
    XFile file, {
    required String otherName,
    String? otherAvatar,
  }) async {
    final outbox = ref.read(outboxServiceProvider);
    if (outbox == null) return;

    final keepAlive = ref.keepAlive();
    state = state.copyWith(isSending: true, clearError: true);

    try {
      final compressed = await MediaCompressService.compressAudio(
        File(file.path),
      );

      if (!ref.mounted) return;

      final currentReply = state.replyTarget;
      final currentReplySender = state.replyTargetSenderName;

      final msg = ChatMessage(
        id: const Uuid().v4(),
        chatId: arg.chatId,
        senderId: arg.currentUserId,
        text: '',
        sentAt: DateTime.now().toUtc(),
        deliveryState: DeliveryState.sending,
        type: MessageType.media,
        uploadProgress: 0.0,
        failure: null,
        replyToMessageId: currentReply?.id,
        replyText: currentReply?.text.isNotEmpty == true
            ? currentReply!.text
            : (currentReply?.media != null
                ? '[${currentReply!.media!.kind.name}]'
                : null),
        replySenderName: currentReplySender ??
            (currentReply != null
                ? (currentReply.senderId == arg.currentUserId
                    ? 'You'
                    : otherName)
                : null),
        replyMediaKind: currentReply?.media?.kind.name,
        media: MessageMedia(
          url: compressed.path,
          kind: MediaKind.audio,
          mime: 'audio/m4a',
          size: compressed.lengthSync(),
        ),
      );

      await outbox.savePending(
        msg,
        otherUserId: arg.otherUserId,
        otherAvatar: otherAvatar,
      );
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, clearReplyTarget: true);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(isSending: false, error: e.toString());
      }
    } finally {
      keepAlive.close();
    }
  }

  Future<void> sendVoice(
    File recordedFile,
    int durationMs, {
    required String otherName,
    String? otherAvatar,
  }) async {
    final outbox = ref.read(outboxServiceProvider);
    if (outbox == null) return;

    final keepAlive = ref.keepAlive();
    state = state.copyWith(isSending: true, clearError: true);

    try {
      final compressed = await MediaCompressService.compressAudio(recordedFile);

      if (!ref.mounted) return;

      final currentReply = state.replyTarget;
      final currentReplySender = state.replyTargetSenderName;

      final msg = ChatMessage(
        id: const Uuid().v4(),
        chatId: arg.chatId,
        senderId: arg.currentUserId,
        text: '',
        sentAt: DateTime.now().toUtc(),
        deliveryState: DeliveryState.sending,
        type: MessageType.media,
        uploadProgress: 0.0,
        failure: null,
        replyToMessageId: currentReply?.id,
        replyText: currentReply?.text.isNotEmpty == true
            ? currentReply!.text
            : (currentReply?.media != null
                ? '[${currentReply!.media!.kind.name}]'
                : null),
        replySenderName: currentReplySender ??
            (currentReply != null
                ? (currentReply.senderId == arg.currentUserId
                    ? 'You'
                    : otherName)
                : null),
        replyMediaKind: currentReply?.media?.kind.name,
        media: MessageMedia(
          url: compressed.path,
          kind: MediaKind.audio,
          mime: 'audio/m4a',
          size: compressed.lengthSync(),
          durationMs: durationMs,
        ),
      );

      await outbox.savePending(
        msg,
        otherUserId: arg.otherUserId,
        otherAvatar: otherAvatar,
      );
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, clearReplyTarget: true);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(isSending: false, error: e.toString());
      }
    } finally {
      keepAlive.close();
    }
  }

  Future<void> sendDocument(
    XFile file, {
    required String otherName,
    String? otherAvatar,
  }) async {
    final outbox = ref.read(outboxServiceProvider);
    if (outbox == null) return;

    final keepAlive = ref.keepAlive();
    state = state.copyWith(isSending: true, clearError: true);

    try {
      final docFile = File(file.path);

      final currentReply = state.replyTarget;
      final currentReplySender = state.replyTargetSenderName;

      final msg = ChatMessage(
        id: const Uuid().v4(),
        chatId: arg.chatId,
        senderId: arg.currentUserId,
        text: file.name,
        sentAt: DateTime.now().toUtc(),
        deliveryState: DeliveryState.sending,
        type: MessageType.media,
        uploadProgress: 0.0,
        failure: null,
        replyToMessageId: currentReply?.id,
        replyText: currentReply?.text.isNotEmpty == true
            ? currentReply!.text
            : (currentReply?.media != null
                ? '[${currentReply!.media!.kind.name}]'
                : null),
        replySenderName: currentReplySender ??
            (currentReply != null
                ? (currentReply.senderId == arg.currentUserId
                    ? 'You'
                    : otherName)
                : null),
        replyMediaKind: currentReply?.media?.kind.name,
        media: MessageMedia(
          url: docFile.path,
          kind: MediaKind.document,
          mime: file.mimeType ?? 'application/octet-stream',
          size: docFile.lengthSync(),
        ),
      );

      await outbox.savePending(
        msg,
        otherUserId: arg.otherUserId,
        otherAvatar: otherAvatar,
      );
      if (!ref.mounted) return;
      state = state.copyWith(isSending: false, clearReplyTarget: true);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(isSending: false, error: e.toString());
      }
    } finally {
      keepAlive.close();
    }
  }

  /// Unified manual retry for both text (via [OutboxDaemon]) and media (via [OutboxService]) messages.
  Future<void> retryMessage(String messageId) async {
    final keepAlive = ref.keepAlive();
    try {
      final repo = ref.read(messagesRepositoryProvider);
      final activeDb = HiveDatabaseManager.instance.activeDatabase;
      final daemon = repo?.outboxDaemon ?? activeDb?.outboxDaemon;

      // 1. Check if the message is in OutboxStore
      final outboxStore = activeDb?.outboxStore;
      final outboxEntry = outboxStore?.getById(messageId);

      if (outboxEntry != null && daemon != null) {
        debugPrint(
          '[ChatSendNotifier] Retrying message $messageId via OutboxDaemon',
        );
        await daemon.retryExhausted(messageId);
        return;
      }

      // 2. Delegate to MessagesRepository if attached
      if (daemon != null && repo != null) {
        await repo.retryMessage(messageId);
      }

      // 3. Fall back to OutboxService (for media uploads or legacy records)
      final outbox = ref.read(outboxServiceProvider);
      if (outbox != null) {
        debugPrint(
          '[ChatSendNotifier] Retrying message $messageId via OutboxService',
        );
        await outbox.retryMessage(messageId);
      }

      // 4. If message is marked failed in MessagesStore and was absent from OutboxStore, re-enqueue
      final msgStore = repo?.messagesStore ?? activeDb?.messagesStore;
      final msg = msgStore?.getMessage(messageId);
      if (msg != null && daemon != null && outboxEntry == null) {
        debugPrint(
          '[ChatSendNotifier] Re-enqueuing failed message $messageId into OutboxDaemon',
        );
        await msgStore!.updateDelivery(
          messageId,
          DeliveryState.sending,
          failure: null,
        );
        await daemon.enqueueMessage(message: msg, accountId: msg.senderId);
      }
    } catch (e) {
      debugPrint('[ChatSendNotifier] retryMessage error for $messageId: $e');
    } finally {
      keepAlive.close();
    }
  }

  @Deprecated('Use retryMessage instead')
  Future<void> retryMediaMessage(String messageId) => retryMessage(messageId);

  Future<void> cancelMediaMessage(String messageId) async {
    final outbox = ref.read(outboxServiceProvider);
    if (outbox != null) {
      final keepAlive = ref.keepAlive();
      try {
        await outbox.cancelMessage(messageId);
      } finally {
        keepAlive.close();
      }
    }
  }
}
