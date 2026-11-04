/// Result payload returned upon successful media upload.
class StorageUploadResult {
  /// Storage bucket name (e.g. 'avatars' or 'attachments').
  final String bucket;

  /// Object path within the bucket (e.g. '{userId}/avatar.jpg').
  final String path;

  /// Public URL (for public buckets) or canonical access URL.
  final String publicUrl;

  /// MIME type of the uploaded file.
  final String? mimeType;

  /// File size in bytes.
  final int fileSizeBytes;

  const StorageUploadResult({
    required this.bucket,
    required this.path,
    required this.publicUrl,
    this.mimeType,
    required this.fileSizeBytes,
  });

  @override
  String toString() =>
      'StorageUploadResult(bucket: $bucket, path: $path, size: $fileSizeBytes)';
}

/// Provider-independent contract for media storage operations.
///
/// Decouples controllers and background executors from underlying storage SDKs
/// (Supabase Storage, Cloudinary, etc.).
abstract class MediaStorageService {
  /// Uploads a user or group avatar image.
  ///
  /// Avatars are stored in a public bucket for app-wide profile display.
  Future<StorageUploadResult> uploadAvatar({
    required String ownerType, // 'user' or 'group'
    required String ownerId,
    required String filePath,
  });

  /// Uploads a chat attachment (image, video, audio, or document).
  ///
  /// Attachments are stored in a private bucket with membership-enforced access.
  Future<StorageUploadResult> uploadChatAttachment({
    required String chatId,
    required String messageId,
    required String filePath,
    required String mediaKind, // 'image', 'video', 'audio', 'document'
    String? mimeType,
  });

  /// Generates an authorized access URL for private objects.
  Future<String> getAuthorizedUrl({
    required String bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  });

  /// Deletes an object from storage.
  Future<void> deleteFile({required String bucket, required String path});
}
