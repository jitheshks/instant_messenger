import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown when a file path attempts to escape the designated sandbox directory.
class PathTraversalException implements Exception {
  final String path;
  const PathTraversalException(this.path);

  @override
  String toString() =>
      'PathTraversalException: Access denied to path outside sandbox: $path';
}

/// Exception thrown when file storage exceeds allocated disk quota limits.
class StorageQuotaExceededException implements Exception {
  final int requestedBytes;
  final int currentBytes;
  final int maxBytesQuota;

  const StorageQuotaExceededException({
    required this.requestedBytes,
    required this.currentBytes,
    required this.maxBytesQuota,
  });

  @override
  String toString() =>
      'StorageQuotaExceededException: Operation requires $requestedBytes bytes, '
      'but current usage ($currentBytes bytes) + requested exceeds quota ($maxBytesQuota bytes).';
}

/// Provides sandboxed local file storage with quota controls, hash verification,
/// and traversal protection for attachments, avatars, and audio recordings.
class LocalFileStorage {
  final Directory? _injectedBaseDir;

  LocalFileStorage({Directory? baseDir}) : _injectedBaseDir = baseDir;

  /// Retrieves the root sandboxed directory.
  Future<Directory> get baseDirectory async {
    final injected = _injectedBaseDir;
    if (injected != null) {
      if (!await injected.exists()) {
        await injected.create(recursive: true);
      }
      return injected;
    }
    final docDir = await getApplicationDocumentsDirectory();
    final messengerDir = Directory(
      p.join(docDir.path, 'instant_messenger_storage'),
    );
    if (!await messengerDir.exists()) {
      await messengerDir.create(recursive: true);
    }
    return messengerDir;
  }

  /// Sanitizes and validates that [relativePath] does not escape the sandbox root.
  Future<File> _resolveSafeFile(String subDir, String fileName) async {
    final root = await baseDirectory;
    final rootCanonical = p.canonicalize(root.path);

    // Normalize and prevent path traversal
    final combined = p.normalize(p.join(rootCanonical, subDir, fileName));
    final canonicalTarget = p.canonicalize(combined);

    if (!p.isWithin(rootCanonical, canonicalTarget) &&
        canonicalTarget != rootCanonical) {
      throw PathTraversalException('$subDir/$fileName');
    }

    return File(canonicalTarget);
  }

  /// Resolves the safe directory path for a given [subDir].
  Future<Directory> _resolveSafeDir(String subDir) async {
    final root = await baseDirectory;
    final rootCanonical = p.canonicalize(root.path);
    final combined = p.normalize(p.join(rootCanonical, subDir));
    final canonicalTarget = p.canonicalize(combined);

    if (!p.isWithin(rootCanonical, canonicalTarget) &&
        canonicalTarget != rootCanonical) {
      throw PathTraversalException(subDir);
    }

    return Directory(canonicalTarget);
  }

  /// Computes the SHA-256 hex digest of the supplied byte array.
  String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Saves [bytes] into `[subDir]/[fileName]`, checking quota first.
  Future<File> saveFile({
    required String subDir,
    required String fileName,
    required List<int> bytes,
    int maxQuotaBytes = 500 * 1024 * 1024, // 500 MB default quota
  }) async {
    final isWithinQuota = await checkQuota(
      incomingBytes: bytes.length,
      maxQuotaBytes: maxQuotaBytes,
    );
    if (!isWithinQuota) {
      final currentSize = await getTotalStorageSizeBytes();
      throw StorageQuotaExceededException(
        requestedBytes: bytes.length,
        currentBytes: currentSize,
        maxBytesQuota: maxQuotaBytes,
      );
    }

    final file = await _resolveSafeFile(subDir, fileName);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    return await file.writeAsBytes(bytes, flush: true);
  }

  /// Retrieves a file from `[subDir]/[fileName]`. Returns null if it does not exist.
  Future<File?> getFile({
    required String subDir,
    required String fileName,
  }) async {
    final file = await _resolveSafeFile(subDir, fileName);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Deletes a file from `[subDir]/[fileName]`. Returns true if deleted, false if did not exist.
  Future<bool> deleteFile({
    required String subDir,
    required String fileName,
  }) async {
    final file = await _resolveSafeFile(subDir, fileName);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Calculates the total size in bytes of files within [subDir].
  Future<int> getDirectorySizeBytes(String subDir) async {
    final dir = await _resolveSafeDir(subDir);
    if (!await dir.exists()) return 0;

    int totalBytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  /// Calculates total size of all stored sandbox data across all subdirectories.
  Future<int> getTotalStorageSizeBytes() async {
    final root = await baseDirectory;
    int totalBytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  /// Checks if [incomingBytes] can be saved without exceeding [maxQuotaBytes].
  Future<bool> checkQuota({
    required int incomingBytes,
    int maxQuotaBytes = 500 * 1024 * 1024,
  }) async {
    final currentSize = await getTotalStorageSizeBytes();
    return (currentSize + incomingBytes) <= maxQuotaBytes;
  }

  /// Clears all files inside [subDir].
  Future<void> clearDirectory(String subDir) async {
    final dir = await _resolveSafeDir(subDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
