import 'dart:io';
import 'package:flutter/material.dart';
import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/widgets/chat_delivery_row.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final bool isSelected;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
bool _isLocalMissing(MessageMedia media) {
  return media.url.startsWith('/') && !File(media.url).existsSync();
}



bool _isUploading(ChatMessage msg) {
  return msg.type == MessageType.media &&
      msg.uploadProgress != null &&
      !msg.hasFailed;
}


bool _isUploadFailed(ChatMessage msg) {
  return msg.type == MessageType.media &&
      msg.failure == MessageFailureReason.uploadFailed;
}


  const ChatBubble({
    super.key,
    required this.msg,
    required this.isMe,
    this.isSelected = false,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.72;

    final bubbleColor = isMe ? const Color(0xFFE7FFC4) : Colors.white;

    final selectionInk = isSelected
        ? (isMe
            ? const Color(0xFFDCF8C6).withOpacity(0.40)
            : Colors.grey.shade300.withOpacity(0.30))
        : Colors.transparent;

    final textStyle =
        Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 16, height: 1.25);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(2),
      bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(12),
    );


    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: [
          if (isSelected)
            Positioned.fill(child: Container(color: selectionInk)),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: _buildAnimatedBubble(
  context,
  maxW,
  bubbleColor,
  radius,
  textStyle,
),

              ),
            ],
          ),
        ],
      ),
    );
  }


Widget _uploadingOverlay(double progress) {
  return Positioned.fill(
    child: Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
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
              value: progress,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}



Widget _uploadFailedOverlay() {
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
Widget _buildAnimatedBubble(
  BuildContext context,
  double maxW,
  Color bubbleColor,
  BorderRadius radius,
  TextStyle textStyle,
) {
    Widget bubble = Container(
      margin: EdgeInsets.only(right: isMe ? 6 : 0, left: isMe ? 0 : 6),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
     child: msg.type == MessageType.text
    ? _buildTextLayout(textStyle, maxW)
    : _buildMedia(msg.media, maxW),


    );

    if (msg.deliveryState == DeliveryState.sending) {
      bubble = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: bubble,
      );
    }

    return bubble;
  }



  Widget _buildMedia(MessageMedia? media, double maxW) {
    if (media == null) return const Text('Media unavailable');

  final localMissing = _isLocalMissing(media);

    // ⬇️ Receiver download
    if (!isMe && localMissing) {
      return GestureDetector(
        onTap: onRetry,
        child: _downloadPlaceholder(maxW),
      );
    }

    // 🧨 Sender lost local file
    if (isMe && localMissing) {
      return _unavailablePlaceholder(maxW);
    }

   final isUploading = _isUploading(msg);

final uploadFailed = _isUploadFailed(msg);

final content = Padding(
  padding: isMe
      ? const EdgeInsets.only(right: 36, bottom: 18) // reserve space for ticks
      : EdgeInsets.zero,
  child: _renderMediaContent(media, maxW),
);
return Stack(
  children: [
    content,

    if (isMe && !isUploading && !uploadFailed)
      Positioned(
        right: 6,
        bottom: 6,
        child: ChatDeliveryRow(
          msg: msg,
          onRetry: onRetry,
        ),
      ),

    if (isUploading) _uploadingOverlay(msg.uploadProgress!),
    if (uploadFailed) _uploadFailedOverlay(),
  ],
);



  }



  Widget _buildTextLayout(TextStyle textStyle, double maxW) {
  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 6,
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW - 80),
        child: Text(
          msg.text,
          style: textStyle,
          textAlign: isMe ? TextAlign.right : TextAlign.left,
        ),
      ),

      if (isMe)
        ChatDeliveryRow(
          msg: msg,
          onRetry: onRetry,
        ),
    ],
  );
}


  Widget _downloadPlaceholder(double maxW) => Container(
        width: maxW * 0.9,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download, size: 36),
            SizedBox(height: 8),
            Text('Tap to download'),
          ],
        ),
      );



Widget _renderMediaContent(MessageMedia media, double maxW) {
  final bool isLocal = media.url.startsWith('/');

  if (media.kind == MediaKind.image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: isLocal
          ? Image.file(
              File(media.url),
              width: maxW * 0.9,
              fit: BoxFit.cover,
            )
          : Image.network(
              media.url,
              width: maxW * 0.9,
              fit: BoxFit.cover,
            ),
    );
  }

  // 📄 audio / video / document
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        media.kind == MediaKind.video
            ? Icons.videocam
            : media.kind == MediaKind.audio
                ? Icons.audiotrack
                : Icons.insert_drive_file,
      ),
      const SizedBox(width: 6),
      Text(media.kind.name),
    ],
  );
}


  Widget _unavailablePlaceholder(double maxW) => Container(
        width: maxW * 0.9,
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Media unavailable',
            style: TextStyle(color: Colors.grey)),
      );
}
