import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Metadata for a media attachment tracked in Hive CE local storage.
class AttachmentEntry {
  final String id;
  final String messageId;
  final String localPath;
  final String? remotePath;
  final MediaKind mediaKind;
  final String mimeType;
  final int fileSizeBytes;
  final String uploadStatus; // 'pending', 'uploading', 'completed', 'failed'
  final double uploadProgress; // 0.0 to 1.0
  final DateTime createdAt;

  const AttachmentEntry({
    required this.id,
    required this.messageId,
    required this.localPath,
    this.remotePath,
    required this.mediaKind,
    required this.mimeType,
    required this.fileSizeBytes,
    this.uploadStatus = 'pending',
    this.uploadProgress = 0.0,
    required this.createdAt,
  });

  AttachmentEntry copyWith({
    String? remotePath,
    String? uploadStatus,
    double? uploadProgress,
  }) {
    return AttachmentEntry(
      id: id,
      messageId: messageId,
      localPath: localPath,
      remotePath: remotePath ?? this.remotePath,
      mediaKind: mediaKind,
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'messageId': messageId,
    'localPath': localPath,
    if (remotePath != null) 'remotePath': remotePath,
    'mediaKind': mediaKind.name,
    'mimeType': mimeType,
    'fileSizeBytes': fileSizeBytes,
    'uploadStatus': uploadStatus,
    'uploadProgress': uploadProgress,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory AttachmentEntry.fromMap(Map m) => AttachmentEntry(
    id: m['id'] as String,
    messageId: m['messageId'] as String,
    localPath: m['localPath'] as String,
    remotePath: m['remotePath'] as String?,
    mediaKind: MediaKind.values.firstWhere(
      (k) => k.name == m['mediaKind'],
      orElse: () => MediaKind.image,
    ),
    mimeType: (m['mimeType'] as String?) ?? 'application/octet-stream',
    fileSizeBytes: (m['fileSizeBytes'] as int?) ?? 0,
    uploadStatus: (m['uploadStatus'] as String?) ?? 'pending',
    uploadProgress: ((m['uploadProgress'] as num?) ?? 0.0).toDouble(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
