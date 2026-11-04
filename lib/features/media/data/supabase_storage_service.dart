import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'media_storage_service.dart';

/// Supabase Storage implementation of [MediaStorageService].
///
/// Stores profile avatars in the public `avatars` bucket and chat media attachments
/// in the private `attachments` bucket with conversation-membership RLS security.
class SupabaseStorageService implements MediaStorageService {
  final SupabaseClient? _injectedClient;

  SupabaseStorageService([this._injectedClient]);

  /// Resolves the active [SupabaseClient], preferring an injected client (e.g. for testing)
  /// or falling back to the singleton [Supabase.instance.client].
  SupabaseClient get client {
    if (_injectedClient != null) {
      return _injectedClient;
    }
    return Supabase.instance.client;
  }

  static const String avatarBucket = 'avatars';
  static const String attachmentBucket = 'attachments';

  @override
  Future<StorageUploadResult> uploadAvatar({
    required String ownerType,
    required String ownerId,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileNotFoundException('Avatar file does not exist: $filePath');
    }

    final fileSizeBytes = await file.length();
    if (fileSizeBytes == 0) {
      throw const FormatException('Avatar file is empty (0 bytes).');
    }

    final ext = p.extension(filePath).toLowerCase();
    final cleanExt = ext.isNotEmpty ? ext : '.jpg';
    final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';

    // Bucket policy expects first folder segment to be ownerId: "{ownerId}/avatar_{timestamp}.ext"
    final objectName =
        '$ownerId/avatar_${DateTime.now().millisecondsSinceEpoch}$cleanExt';

    debugPrint(
      '[SupabaseStorageService] Uploading avatar: $objectName ($fileSizeBytes bytes)',
    );

    try {
      await client.storage
          .from(avatarBucket)
          .upload(
            objectName,
            file,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      final publicUrl = client.storage
          .from(avatarBucket)
          .getPublicUrl(objectName);
      debugPrint(
        '[SupabaseStorageService] Avatar uploaded. Public URL: $publicUrl',
      );

      return StorageUploadResult(
        bucket: avatarBucket,
        path: objectName,
        publicUrl: publicUrl,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
      );
    } catch (e, st) {
      debugPrint('[SupabaseStorageService] ❌ Avatar upload failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<StorageUploadResult> uploadChatAttachment({
    required String chatId,
    required String messageId,
    required String filePath,
    required String mediaKind,
    String? mimeType,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileNotFoundException('Attachment file does not exist: $filePath');
    }

    final fileSizeBytes = await file.length();
    if (fileSizeBytes == 0) {
      throw const FormatException('Attachment file is empty (0 bytes).');
    }

    final resolvedMime =
        mimeType ?? lookupMimeType(filePath) ?? 'application/octet-stream';
    final baseName = p.basename(filePath);
    // Bucket policy expects first folder segment to be chatId: "{chatId}/{messageId}_{filename}"
    final objectName = '$chatId/${messageId}_$baseName';

    debugPrint(
      '[SupabaseStorageService] Uploading attachment: $objectName ($resolvedMime)',
    );

    try {
      await client.storage
          .from(attachmentBucket)
          .upload(
            objectName,
            file,
            fileOptions: FileOptions(contentType: resolvedMime, upsert: true),
          );

      // For private attachments, the stored reference is the canonical path.
      // Callers generate temporary signed URLs as needed via getAuthorizedUrl.
      debugPrint(
        '[SupabaseStorageService] Attachment uploaded successfully: $objectName',
      );

      return StorageUploadResult(
        bucket: attachmentBucket,
        path: objectName,
        publicUrl:
            objectName, // Stores stable path; use getAuthorizedUrl for display
        mimeType: resolvedMime,
        fileSizeBytes: fileSizeBytes,
      );
    } catch (e, st) {
      debugPrint('[SupabaseStorageService] ❌ Attachment upload failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<String> getAuthorizedUrl({
    required String bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    try {
      final signedUrl = await client.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn.inSeconds);
      return signedUrl;
    } catch (e) {
      debugPrint(
        '[SupabaseStorageService] Error creating signed URL for $bucket/$path: $e',
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      await client.storage.from(bucket).remove([path]);
      debugPrint('[SupabaseStorageService] Deleted object: $bucket/$path');
    } catch (e) {
      debugPrint('[SupabaseStorageService] Error deleting $bucket/$path: $e');
      rethrow;
    }
  }
}

class FileNotFoundException implements Exception {
  final String message;
  const FileNotFoundException(this.message);
  @override
  String toString() => 'FileNotFoundException: $message';
}
