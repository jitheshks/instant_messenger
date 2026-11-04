import 'package:instant_messenger/features/media/data/media_storage_service.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';

class UploadOrchestrator {
  final MediaStorageService storage;
  final OutboxService outbox;

  UploadOrchestrator({required this.storage, required this.outbox});

  Future<String> uploadAvatar({
    required String ownerType,
    required String ownerId,
    required String filePath,
  }) async {
    try {
      final result = await storage.uploadAvatar(
        ownerType: ownerType,
        ownerId: ownerId,
        filePath: filePath,
      );

      return result.publicUrl;
    } catch (_) {
      await outbox.enqueueAvatarUpload(
        ownerType: ownerType,
        ownerId: ownerId,
        filePath: filePath,
      );
      rethrow;
    }
  }

  /// Uploads a chat attachment using the active storage provider.
  Future<StorageUploadResult> uploadChatAttachment({
    required String chatId,
    required String messageId,
    required String filePath,
    required String mediaKind,
    String? mimeType,
  }) async {
    return storage.uploadChatAttachment(
      chatId: chatId,
      messageId: messageId,
      filePath: filePath,
      mediaKind: mediaKind,
      mimeType: mimeType,
    );
  }

  /// Generates an authorized access URL for private bucket objects.
  Future<String> getAuthorizedUrl({
    required String bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    return storage.getAuthorizedUrl(
      bucket: bucket,
      path: path,
      expiresIn: expiresIn,
    );
  }
}
