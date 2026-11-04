// lib/features/messaging/presentation/widgets/call_bubble.dart

import 'package:flutter/material.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';

/// WhatsApp-style in-chat call event bubble displaying modality, direction,
/// status, duration, and one-tap call back action.
class CallBubble extends StatelessWidget {
  final CallRecord call;
  final String currentUserId;
  final VoidCallback? onCallBack;

  const CallBubble({
    super.key,
    required this.call,
    required this.currentUserId,
    this.onCallBack,
  });

  @override
  Widget build(BuildContext context) {
    final chatTheme = ChatThemeExtension.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isOutgoing = call.isOutgoing(currentUserId);
    final isMissed = call.isMissed;
    final isDeclined = call.isDeclined;
    final isCancelled = call.isCancelled;
    final isVideo = call.callType == CallType.video;

    // Visual configuration
    final Color iconColor;
    final IconData statusIcon;
    final String titleText;
    final String subtitleText;

    if (isMissed) {
      iconColor = cs.error;
      statusIcon = isVideo ? Icons.videocam_off_outlined : Icons.call_missed;
      titleText = isVideo ? 'Missed video call' : 'Missed voice call';
      subtitleText = 'Tap to call back';
    } else if (isCancelled) {
      iconColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
      statusIcon = isVideo ? Icons.videocam_outlined : Icons.call_end_outlined;
      titleText = isVideo ? 'Cancelled video call' : 'Cancelled voice call';
      subtitleText = 'Not answered';
    } else if (isDeclined) {
      iconColor = cs.error;
      statusIcon = isVideo ? Icons.videocam_off_outlined : Icons.phone_disabled_outlined;
      titleText = isVideo ? 'Declined video call' : 'Declined voice call';
      subtitleText = isOutgoing ? 'Declined by recipient' : 'Declined';
    } else if (isOutgoing) {
      iconColor = cs.primary;
      statusIcon = isVideo ? Icons.videocam_outlined : Icons.call_made;
      titleText = isVideo ? 'Outgoing video call' : 'Outgoing voice call';
      subtitleText = call.durationSeconds != null && call.durationSeconds! > 0
          ? call.formattedDuration
          : (call.isCompleted ? 'Ended' : 'Completed');
    } else {
      iconColor = cs.primary;
      statusIcon = isVideo ? Icons.videocam_outlined : Icons.call_received;
      titleText = isVideo ? 'Incoming video call' : 'Incoming voice call';
      subtitleText = call.durationSeconds != null && call.durationSeconds! > 0
          ? call.formattedDuration
          : (call.isCompleted ? 'Ended' : 'Completed');
    }

    final bubbleBg = chatTheme.bubbleReceived;

    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Center(
        child: InkWell(
          onTap: onCallBack,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Direction / Modality Icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),

                // Call Description & Duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titleText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            subtitleText,
                            style: TextStyle(
                              fontSize: 12,
                              color: isMissed ? Colors.red.shade400 : subtextColor,
                            ),
                          ),
                          Text(
                            _formatCallTime(call.startedAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: subtextColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Action to call back
                if (onCallBack != null)
                  IconButton(
                    icon: Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      color: cs.primary,
                      size: 20,
                    ),
                    onPressed: onCallBack,
                    tooltip: isVideo ? 'Video call back' : 'Voice call back',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCallTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
