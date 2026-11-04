// lib/features/messaging/presentation/widgets/chat_bubble_media.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Presentation widget for rendering media attachments within a chat bubble.
///
/// Encapsulates image rendering, audio/video/document modality previews,
/// download/unavailable placeholders, upload progress overlays, and retry actions.
class ChatBubbleMedia extends StatelessWidget {
  final MessageMedia? media;
  final bool isMe;
  final double maxWidth;
  final Color textColor;
  final double? uploadProgress;
  final bool isUploadFailed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final Widget? deliveryRow;

  const ChatBubbleMedia({
    super.key,
    required this.media,
    required this.isMe,
    required this.maxWidth,
    required this.textColor,
    this.uploadProgress,
    this.isUploadFailed = false,
    this.onRetry,
    this.onCancel,
    this.deliveryRow,
  });

  bool get _isUploading => uploadProgress != null && !isUploadFailed;

  bool _isLocalMissing(MessageMedia media) {
    return media.url.startsWith('/') && !File(media.url).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    if (media == null) {
      return Text('Media unavailable', style: TextStyle(color: textColor));
    }

    final localMissing = _isLocalMissing(media!);

    // Receiver download placeholder
    if (!isMe && localMissing) {
      return GestureDetector(
        onTap: onRetry,
        child: _buildDownloadPlaceholder(context),
      );
    }

    // Sender lost local file placeholder
    if (isMe && localMissing) {
      return _buildUnavailablePlaceholder(context);
    }

    final content = Padding(
      padding: isMe
          ? const EdgeInsets.only(right: 36, bottom: 18) // reserve space for ticks
          : EdgeInsets.zero,
      child: _renderMediaContent(media!),
    );

    return Stack(
      children: [
        content,
        if (isMe && !_isUploading && !isUploadFailed && deliveryRow != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: deliveryRow!,
          ),
        if (_isUploading) _buildUploadingOverlay(),
        if (isUploadFailed) _buildUploadFailedOverlay(),
      ],
    );
  }

  Widget _buildDownloadPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: maxWidth * 0.9,
      height: 160,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.download, size: 36, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Tap to download', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildUnavailablePlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: maxWidth * 0.9,
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Media unavailable',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _renderMediaContent(MessageMedia media) {
    final bool isLocal = media.url.startsWith('/');

    if (media.kind == MediaKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isLocal
            ? Image.file(
                File(media.url),
                width: maxWidth * 0.9,
                fit: BoxFit.cover,
              )
            : Image.network(
                media.url,
                width: maxWidth * 0.9,
                fit: BoxFit.cover,
              ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          media.kind == MediaKind.video
              ? Icons.videocam
              : media.kind == MediaKind.audio
              ? Icons.audiotrack
              : Icons.insert_drive_file,
          color: textColor,
        ),
        const SizedBox(width: 6),
        Text(media.kind.name, style: TextStyle(color: textColor)),
      ],
    );
  }

  Widget _buildUploadingOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            if (onCancel != null)
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: onCancel,
                ),
              ),
            Center(
              child: CircularProgressIndicator(
                value: uploadProgress,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadFailedOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onRetry,
          child: const Center(
            child: Icon(Icons.refresh, color: Colors.white, size: 36),
          ),
        ),
      ),
    );
  }
}
