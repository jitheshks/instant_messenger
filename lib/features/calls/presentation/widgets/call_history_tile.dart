// lib/features/calls/presentation/widgets/call_history_tile.dart

import 'package:flutter/material.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/shared/utils/date_formatter.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Reusable list tile displaying a single historical call log record.
class CallHistoryTile extends StatelessWidget {
  final CallRecord call;
  final String currentUserId;
  final String? resolvedPeerName;
  final VoidCallback? onCallBack;
  final VoidCallback? onTap;

  const CallHistoryTile({
    super.key,
    required this.call,
    required this.currentUserId,
    this.resolvedPeerName,
    this.onCallBack,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOutgoing = call.isOutgoing(currentUserId);
    final theme = Theme.of(context);
    final isMissed = call.isMissed;
    final isVideo = call.callType == CallType.video;

    final peerName = resolvedPeerName ??
        call.peerName ??
        (call.peerPhone?.isNotEmpty == true ? call.peerPhone! : 'Contact');

    final IconData dirIcon;
    final Color dirColor;
    if (isMissed) {
      dirIcon = isVideo ? Icons.videocam_off_outlined : Icons.call_missed;
      dirColor = Colors.red.shade400;
    } else if (isOutgoing) {
      dirIcon = isVideo ? Icons.videocam_outlined : Icons.call_made;
      dirColor = theme.colorScheme.primary;
    } else {
      dirIcon = isVideo ? Icons.videocam_outlined : Icons.call_received;
      dirColor = theme.colorScheme.primary;
    }

    return ListTile(
      leading: SafeAvatar(
        radius: 22,
        avatarUrl: call.peerAvatarUrl,
        fallbackName: peerName,
      ),
      title: Text(
        peerName,
        style: TextStyle(
          fontWeight: isMissed ? FontWeight.bold : FontWeight.w500,
          color: isMissed ? Colors.red.shade400 : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Icon(dirIcon, size: 16, color: dirColor),
          const SizedBox(width: 4),
          Text(
            DateFormatter.formatCallDateTime(call.startedAt),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          if (call.durationSeconds != null && call.durationSeconds! > 0) ...[
            const SizedBox(width: 4),
            Text(
              '(${call.formattedDuration})',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          isVideo ? Icons.videocam : Icons.call,
          color: cs.primary,
        ),
        onPressed: onCallBack,
        tooltip: isVideo ? 'Video call' : 'Voice call',
      ),
      onTap: onTap,
    );
  }
}
