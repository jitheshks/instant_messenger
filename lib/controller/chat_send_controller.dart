// lib/controller/chat_send_controller.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cross_file/cross_file.dart';

import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/services/chat_repository.dart';
import 'package:instant_messenger/services/media_compress_service.dart';
import 'package:instant_messenger/services/outbox_service.dart';
import 'package:instant_messenger/services/video_thumbnail_service.dart';

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
  final ChatRepository repo;
  final OutboxService outbox;

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
    this.onPush,
  });

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
      deliveryState: DeliveryState.sent,
    );

    final serverId = await repo.sendMessage(
      chatId,
      msg,
      otherUserId: otherUserId,
      otherName: otherName,
      otherAvatar: otherAvatar,
    );

    if (onPush != null) {
      await onPush!(
        chatId: chatId,
        senderId: currentUserId,
        preview: msg.text,
        type: 'text',
        messageId: serverId,
        recipientUserIds: [otherUserId],
      );
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

  Future<void> retryMediaMessage(String messageId) async {
    debugPrint('[ChatSend] retryMediaMessage $messageId');
    await outbox.retryMessage(messageId);
  }

  Future<void> cancelMediaMessage(String messageId) async {
    await outbox.cancelMessage(messageId);
  }

  // ---------------- UTIL ----------------

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${currentUserId.substring(0, 6)}';
}
