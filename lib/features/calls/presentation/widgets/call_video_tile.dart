// lib/features/calls/presentation/widgets/call_video_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/calls_providers.dart';

/// Renders either a local camera preview or a remote participant's video stream.
/// Falls back to an avatar placeholder if the camera is disabled or stream has no video.
class CallVideoTile extends ConsumerStatefulWidget {
  final String participantName;
  final String? avatarUrl;
  final String? streamId;
  final bool isLocal;
  final bool isCameraEnabled;
  final bool isMicrophoneMuted;
  final bool isPiP;
  final VoidCallback? onTap;

  const CallVideoTile({
    super.key,
    required this.participantName,
    this.avatarUrl,
    this.streamId,
    required this.isLocal,
    required this.isCameraEnabled,
    this.isMicrophoneMuted = false,
    this.isPiP = false,
    this.onTap,
  });

  @override
  ConsumerState<CallVideoTile> createState() => _CallVideoTileState();
}

class _CallVideoTileState extends ConsumerState<CallVideoTile> {
  Widget? _canvasWidget;
  int? _viewId;
  bool _isLoadingView = false;

  @override
  void initState() {
    super.initState();
    _setupCanvasView();
  }

  @override
  void didUpdateWidget(CallVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCameraEnabled != oldWidget.isCameraEnabled ||
        widget.streamId != oldWidget.streamId) {
      if (widget.isCameraEnabled && _canvasWidget == null) {
        _setupCanvasView();
      }
    }
  }

  Future<void> _setupCanvasView() async {
    if (!widget.isCameraEnabled) return;
    if (_isLoadingView) return;

    setState(() {
      _isLoadingView = true;
    });

    final controller = ref.read(callControllerProvider.notifier);
    final widgetView = await controller.createVideoView((viewId) {
      if (!mounted) return;
      _viewId = viewId;

      if (widget.isLocal) {
        controller.setLocalPreviewView(viewId);
      } else if (widget.streamId != null) {
        controller.setRemoteVideoView(widget.streamId!, viewId);
      }
    });

    if (mounted) {
      setState(() {
        _canvasWidget = widgetView;
        _isLoadingView = false;
      });
    }
  }

  @override
  void dispose() {
    final controller = ref.read(callControllerProvider.notifier);
    final viewId = _viewId;
    if (viewId != null) {
      if (widget.isLocal) {
        controller.setLocalPreviewView(null);
      } else if (widget.streamId != null) {
        controller.setRemoteVideoView(widget.streamId!, null);
      }
      controller.destroyVideoView(viewId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.isCameraEnabled && _canvasWidget != null;

    final content = Stack(
      fit: StackFit.expand,
      children: [
        // 1. Video Canvas or Avatar Placeholder
        if (hasVideo)
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.isPiP ? 12 : 0),
            child: _canvasWidget!,
          )
        else
          Container(
            color: const Color(0xFF1C2230),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: widget.isPiP ? 24 : 44,
                    backgroundColor: Colors.blueGrey.shade700,
                    backgroundImage: (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                    child: (widget.avatarUrl == null || widget.avatarUrl!.isEmpty)
                        ? Text(
                            widget.participantName.isNotEmpty ? widget.participantName[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: widget.isPiP ? 16 : 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  if (!widget.isPiP) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.participantName,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Camera Off',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // 2. Bottom Label Overlay (Name + Mic Status)
        if (!widget.isPiP)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isMicrophoneMuted) ...[
                    const Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.isLocal ? 'You' : widget.participantName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: content,
      );
    }

    return content;
  }
}
