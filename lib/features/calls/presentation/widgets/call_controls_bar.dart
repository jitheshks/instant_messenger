// lib/features/calls/presentation/widgets/call_controls_bar.dart

import 'package:flutter/material.dart';

/// Floating circular action button for calling controls.
class CallActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final String tooltip;
  final bool isActive;

  const CallActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0x33FFFFFF),
    this.iconColor = Colors.white,
    this.size = 56,
    required this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBg = isActive ? Colors.white : backgroundColor;
    final effectiveIconColor = isActive ? Colors.black87 : iconColor;

    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: effectiveBg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(icon, color: effectiveIconColor, size: size * 0.48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Action control bar displayed at the bottom of audio and video calls.
class CallControlsBar extends StatelessWidget {
  final bool isVideoCall;
  final bool isMicrophoneMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  const CallControlsBar({
    super.key,
    required this.isVideoCall,
    required this.isMicrophoneMuted,
    required this.isCameraEnabled,
    required this.isSpeakerOn,
    required this.isFrontCamera,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(36),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Speakerphone toggle
          CallActionButton(
            icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            tooltip: isSpeakerOn ? 'Speaker On' : 'Speaker Off',
            isActive: isSpeakerOn,
            onPressed: onToggleSpeaker,
          ),
          const SizedBox(width: 14),

          // Microphone toggle (Mute / Unmute)
          CallActionButton(
            icon: isMicrophoneMuted ? Icons.mic_off : Icons.mic,
            tooltip: isMicrophoneMuted ? 'Unmute Microphone' : 'Mute Microphone',
            isActive: isMicrophoneMuted,
            onPressed: onToggleMicrophone,
          ),
          const SizedBox(width: 14),

          // Camera toggle (Video enable / disable)
          if (isVideoCall) ...[
            CallActionButton(
              icon: isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              tooltip: isCameraEnabled ? 'Turn Off Camera' : 'Turn On Camera',
              isActive: !isCameraEnabled,
              onPressed: onToggleCamera,
            ),
            const SizedBox(width: 14),

            // Camera flip (Front / Rear)
            if (isCameraEnabled) ...[
              CallActionButton(
                icon: Icons.flip_camera_ios,
                tooltip: isFrontCamera ? 'Switch to Rear Camera' : 'Switch to Front Camera',
                onPressed: onSwitchCamera,
              ),
              const SizedBox(width: 14),
            ],
          ],

          // End Call button (Prominent Red)
          CallActionButton(
            icon: Icons.call_end,
            tooltip: 'End Call',
            backgroundColor: Colors.redAccent.shade700,
            iconColor: Colors.white,
            size: 60,
            onPressed: onEndCall,
          ),
        ],
      ),
    );
  }
}
