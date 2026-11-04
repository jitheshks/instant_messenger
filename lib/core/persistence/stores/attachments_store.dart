import 'package:hive/hive.dart';
import '../models/attachment_entry.dart';

/// Manages media attachment metadata and upload tracking in Hive CE.
class AttachmentsStore {
  final Box _box;

  AttachmentsStore(this._box);

  Box get box => _box;

  Future<void> saveAttachment(AttachmentEntry entry) async {
    await _box.put(entry.id, entry.toMap());
  }

  AttachmentEntry? getAttachment(String id) {
    final raw = _box.get(id);
    if (raw is Map) return AttachmentEntry.fromMap(raw);
    return null;
  }

  List<AttachmentEntry> getAttachmentsForMessage(String messageId) {
    final list = <AttachmentEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          final entry = AttachmentEntry.fromMap(raw);
          if (entry.messageId == messageId) {
            list.add(entry);
          }
        } catch (_) {}
      }
    }
    return list;
  }

  Future<void> updateUploadProgress(
    String id,
    double progress, {
    String? uploadStatus,
    String? remotePath,
  }) async {
    final existing = getAttachment(id);
    if (existing != null) {
      final updated = existing.copyWith(
        uploadProgress: progress,
        uploadStatus: uploadStatus,
        remotePath: remotePath,
      );
      await _box.put(id, updated.toMap());
    }
  }

  Future<void> deleteAttachment(String id) async {
    await _box.delete(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
