// lib/controller/chat_send_controller.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cross_file/cross_file.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:uuid/uuid.dart';

import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/media/data/media_compress_service.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/media/data/video_thumbnail_service.dart';

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

class ChatSendController {
  final MessagesRepository repo;
  final OutboxService outbox;
  final OutboxDaemon? outboxDaemon;

  final String chatId;
  final String currentUserId;
  final String otherUserId;
  final String otherName;
  final String? otherAvatar;

  final OnPushCallback? onPush;

  ChatSendController({
    required this.repo,
    required this.outbox,
    required this.chatId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherName,
    required this.otherAvatar,
    this.outboxDaemon,
    this.onPush,
  }) {
    if (outboxDaemon != null && repo.outboxDaemon == null) {
      repo.attachOutboxDaemon(outboxDaemon!);
    }
  }

  // ---------------- TEXT ----------------

  Future<void> sendCurrentText(String text) async {
    if (text.trim().isEmpty) return;

    final msg = ChatMessage(
      id: _newId(),
      chatId: chatId,
      senderId: currentUserId,
      text: text.trim(),
      sentAt: DateTime.now(),
      type: MessageType.text,
      deliveryState: DeliveryState.sending,
    );

    final serverId = await repo.sendMessage(
      chatId,
      msg,
      otherUserId: otherUserId,
      otherName: otherName,
      otherAvatar: otherAvatar,
    );

    if (onPush != null) {
      onPush!(
        chatId: chatId,
        senderId: currentUserId,
        preview: msg.text,
        type: 'text',
        messageId: serverId,
        recipientUserIds: [otherUserId],
      ).catchError((e) {
        debugPrint('[ChatSendController] Push notice: $e');
      });
    }
  }

  // ---------------- IMAGES / VIDEOS ----------------

  Future<void> sendImages(List<XFile> files, String caption) async {
    if (files.isEmpty) return;

    for (final file in files) {
      final msgId = _newId();
      final originalFile = File(file.path);

      final isVideo = file.path.toLowerCase().endsWith('.mp4');

      File? thumb;
      if (isVideo) {
        thumb = await VideoThumbnailService.generate(file.path);
      }

      final File compressedFile = isVideo
          ? await MediaCompressService.compressVideo(originalFile)
          : await MediaCompressService.compressImage(originalFile);

      final msg = ChatMessage(
        id: msgId,
        chatId: chatId,
        senderId: currentUserId,
        text: caption,
        sentAt: DateTime.now(),
        deliveryState: DeliveryState.sending,
        type: MessageType.media,
        uploadProgress: 0.0,
        failure: null,
        media: MessageMedia(
          url: compressedFile.path, // LOCAL PATH
          thumbUrl: thumb?.path,
          kind: isVideo ? MediaKind.video : MediaKind.image,
          mime: isVideo ? 'video/mp4' : 'image/*',
          size: compressedFile.lengthSync(),
        ),
      );

      await outbox.savePending(msg);
    }
  }

  // ---------------- AUDIO ----------------

  Future<void> sendAudio(XFile file) async {
    final compressed = await MediaCompressService.compressAudio(
      File(file.path),
    );

    final msg = ChatMessage(
      id: _newId(),
      chatId: chatId,
      senderId: currentUserId,
      text: '',
      sentAt: DateTime.now(),
      deliveryState: DeliveryState.sending,
      type: MessageType.media,
      uploadProgress: 0.0,
      failure: null,
      media: MessageMedia(
        url: compressed.path,
        kind: MediaKind.audio,
        mime: 'audio/m4a',
        size: compressed.lengthSync(),
      ),
    );

    await outbox.savePending(msg);
  }

  // ---------------- VOICE ----------------

  Future<void> sendVoice(File recordedFile, int durationMs) async {
    final compressed = await MediaCompressService.compressAudio(recordedFile);

    final msg = ChatMessage(
      id: _newId(),
      chatId: chatId,
      senderId: currentUserId,
      text: '',
      sentAt: DateTime.now(),
      deliveryState: DeliveryState.sending,
      type: MessageType.media,
      uploadProgress: 0.0,
      failure: null,
      media: MessageMedia(
        url: compressed.path,
        kind: MediaKind.audio,
        mime: 'audio/m4a',
        size: compressed.lengthSync(),
        durationMs: durationMs,
      ),
    );

    await outbox.savePending(msg);
  }

  // ---------------- DOCUMENT ----------------

  Future<void> sendDocument(XFile file) async {
    final docFile = File(file.path);

    final msg = ChatMessage(
      id: _newId(),
      chatId: chatId,
      senderId: currentUserId,
      text: file.name,
      sentAt: DateTime.now(),
      deliveryState: DeliveryState.sending,
      type: MessageType.media,
      uploadProgress: 0.0,
      failure: null,
      media: MessageMedia(
        url: docFile.path,
        kind: MediaKind.document,
        mime: file.mimeType ?? 'application/octet-stream',
        size: docFile.lengthSync(),
      ),
    );

    await outbox.savePending(msg);
  }

  // ---------------- RETRY / CANCEL ----------------

  Future<void> retryMessage(String messageId) async {
    debugPrint('[ChatSend] retryMessage $messageId');
    if (outboxDaemon != null) {
      await outboxDaemon!.retryExhausted(messageId);
    }
    await outbox.retryMessage(messageId);
  }

  Future<void> retryMediaMessage(String messageId) => retryMessage(messageId);

  Future<void> cancelMediaMessage(String messageId) async {
    await outbox.cancelMessage(messageId);
  }

  // ---------------- UTIL ----------------

  String _newId() {
    return const Uuid().v4();
  }
}
