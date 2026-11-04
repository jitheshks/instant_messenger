// lib/features/calls/presentation/widgets/group_call_grid.dart

import 'package:flutter/material.dart';
import '../../domain/models/zego_call_models.dart';
import 'call_video_tile.dart';

/// Responsive video/audio participant grid supporting 1-on-1 PiP and multi-user group tiles.
class GroupCallGrid extends StatelessWidget {
  final ZegoCallSession session;
  final String localUserName;
  final String? localAvatarUrl;

  const GroupCallGrid({
    super.key,
    required this.session,
    required this.localUserName,
    this.localAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final remoteParticipants = session.remoteParticipants;
    final totalCount = session.participants.length;

    // 1-on-1 Video Mode: Fullscreen remote + Floating PiP local
    if (totalCount <= 2 && remoteParticipants.length == 1) {
      final remote = remoteParticipants.first;

      return Stack(
        fit: StackFit.expand,
        children: [
          // Remote Participant (Fullscreen)
          CallVideoTile(
            participantName: remote.userName,
            streamId: remote.streamId,
            isLocal: false,
            isCameraEnabled: remote.hasVideo,
            isMicrophoneMuted: !remote.hasAudio,
          ),

          // Local Participant (Floating PiP at top right)
          Positioned(
            top: 48,
            right: 16,
            child: Container(
              width: 110,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CallVideoTile(
                  participantName: localUserName,
                  avatarUrl: localAvatarUrl,
                  streamId: session.localStreamId,
                  isLocal: true,
                  isCameraEnabled: session.isCameraEnabled,
                  isMicrophoneMuted: session.isMicrophoneMuted,
                  isPiP: true,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Group Calling Mode (3 or more participants, or solo local before remote answers)
    final allParticipants = session.participants.values.toList();
    if (allParticipants.isEmpty) {
      return Container(color: Colors.black);
    }

    final crossAxisCount = allParticipants.length <= 4 ? 2 : 2;

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: allParticipants.length <= 2 ? 0.75 : 0.85,
        ),
        itemCount: allParticipants.length,
        itemBuilder: (context, index) {
          final p = allParticipants[index];
          final isLocal = p.isLocal;

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CallVideoTile(
              participantName: isLocal ? '$localUserName (You)' : p.userName,
              avatarUrl: isLocal ? localAvatarUrl : null,
              streamId: isLocal ? session.localStreamId : p.streamId,
              isLocal: isLocal,
              isCameraEnabled: isLocal ? session.isCameraEnabled : p.hasVideo,
              isMicrophoneMuted: isLocal ? session.isMicrophoneMuted : !p.hasAudio,
            ),
          );
        },
      ),
    );
  }
}
