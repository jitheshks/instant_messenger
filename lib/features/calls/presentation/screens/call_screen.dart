// lib/features/calls/presentation/screens/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';

import '../../domain/models/call_enums.dart';
import '../../domain/models/zego_call_models.dart';
import '../providers/calls_providers.dart';
import '../widgets/call_avatar.dart';
import '../widgets/call_controls_bar.dart';
import '../widgets/call_duration_timer.dart';
import '../widgets/group_call_grid.dart';
import '../widgets/invite_participants_sheet.dart';

/// Fullscreen calling screen managing incoming, outgoing ringing,
/// active 1-on-1, and group audio/video calling states.
class CallScreen extends ConsumerStatefulWidget {
  final String callID;
  final String userID;
  final String userName;
  final CallType callType;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    this.callType = CallType.audio,
    this.isIncoming = false,
    Object? config, // Backward-compatible dummy parameter
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late bool _isIncomingRinging;
  bool _isExiting = false;
  bool _isStaleCall = false;
  String? _staleMessage;

  @override
  void initState() {
    super.initState();
    _isIncomingRinging = widget.isIncoming;
    if (widget.isIncoming) {
      unawaited(_checkCallLiveness());
    }
  }

  Future<void> _checkCallLiveness() async {
    try {
      final repo = ref.read(callsRepositoryProvider);
      final record = await repo.getCallById(widget.callID);
      if (record != null && mounted) {
        if (!record.status.isInProgress) {
          setState(() {
            _isStaleCall = true;
            _staleMessage = record.status == CallStatus.missed
                ? 'This call was missed.'
                : 'This call has already ended.';
          });
        }
      }
    } catch (_) {}
  }

  void _safeExit() {
    if (_isExiting || !mounted) return;
    _isExiting = true;
    try {
      if (context.canPop()) {
        context.pop();
        return;
      }
    } catch (_) {}

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    try {
      context.go('/chats');
    } catch (_) {}
  }

  Future<void> _handleAcceptIncoming() async {
    setState(() {
      _isIncomingRinging = false;
    });

    final success = await ref.read(callControllerProvider.notifier).acceptIncomingCall(
      callId: widget.callID,
      callType: widget.callType,
      localUserName: widget.userName,
    );

    if (!success && mounted) {
      final error = ref.read(callControllerProvider).errorMessage ?? 'Call is no longer active.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 3)),
      );
      _safeExit();
    }
  }

  Future<void> _handleDeclineIncoming() async {
    await ref.read(callControllerProvider.notifier).rejectIncomingCall(widget.callID);
    _safeExit();
  }

  Future<void> _handleEndCall() async {
    await ref.read(callControllerProvider.notifier).endCall();
    _safeExit();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callControllerProvider);

    // Auto-exit if call terminated while on screen
    ref.listen<ZegoCallSession>(callControllerProvider, (previous, next) {
      if (previous != null && previous.isActive && !next.isActive && !_isIncomingRinging) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _safeExit();
        });
      }
    });

    // 1. Incoming Call Ringing Interface
    if (_isIncomingRinging) {
      return _buildIncomingCallView();
    }

    // 2. Active or Outgoing Call Interface
    final isVideo = session.callType == CallType.video || widget.callType == CallType.video;
    final isEstablished = session.isCallEstablished;
    final statusLabel = isEstablished
        ? 'Connected'
        : (session.connectionState == ZegoRoomConnectionState.reconnecting
            ? 'Reconnecting...'
            : 'Ringing...');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleEndCall();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.darkScaffold,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media Content (Audio Avatar or Video Grid)
              if (isVideo && session.isActive)
                GroupCallGrid(
                  session: session,
                  localUserName: widget.userName,
                )
              else
                Center(
                  child: CallAvatar(
                    name: widget.userName,
                    statusText: statusLabel,
                    radius: 72,
                    trailingSubtitle: isEstablished
                        ? CallDurationTimer(
                            isRunning: isEstablished,
                            style: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),

              // Top Bar Header (Call type, duration, add participant button)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo ? Icons.videocam : Icons.call,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                    // Add participant button (for group or expanding active call)
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                      ),
                      tooltip: 'Add Participant',
                      onPressed: () {
                        final currentIds = session.participants.keys.toList();
                        InviteParticipantsSheet.show(context, currentIds);
                      },
                    ),
                  ],
                ),
              ),

              // Bottom Action Controls
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: CallControlsBar(
                    isVideoCall: isVideo,
                    isMicrophoneMuted: session.isMicrophoneMuted,
                    isCameraEnabled: session.isCameraEnabled,
                    isSpeakerOn: session.isSpeakerOn,
                    isFrontCamera: session.isFrontCamera,
                    onToggleMicrophone: () {
                      ref.read(callControllerProvider.notifier).toggleMicrophone();
                    },
                    onToggleCamera: () {
                      ref.read(callControllerProvider.notifier).toggleCamera();
                    },
                    onSwitchCamera: () {
                      ref.read(callControllerProvider.notifier).switchCamera();
                    },
                    onToggleSpeaker: () {
                      ref.read(callControllerProvider.notifier).toggleSpeaker();
                    },
                    onEndCall: _handleEndCall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the full-screen Incoming Call UI with Accept and Decline buttons.
  Widget _buildIncomingCallView() {
    final isVideo = widget.callType == CallType.video;

    return Scaffold(
      backgroundColor: AppColors.darkScaffold,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 40),

            // Caller Info & Incoming Header
            CallAvatar(
              name: widget.userName,
              statusText: _isStaleCall
                  ? 'Call Ended'
                  : (isVideo ? 'Incoming Video Call...' : 'Incoming Voice Call...'),
              radius: 80,
            ),

            if (_isStaleCall)
              Padding(
                padding: const EdgeInsets.only(bottom: 48, left: 40, right: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _staleMessage ?? 'This call is no longer active.',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      key: const Key('btn_dismiss_stale_call'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: _safeExit,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              )
            else
              // Accept / Decline Action Controls
              Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 40, right: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Decline Button (Red)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        key: const Key('btn_decline_call'),
                        heroTag: 'btn_decline_call',
                        backgroundColor: Colors.redAccent.shade700,
                        elevation: 4,
                        onPressed: _handleDeclineIncoming,
                        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Decline',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),

                  // Accept Button (Green)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        key: const Key('btn_accept_call'),
                        heroTag: 'btn_accept_call',
                        backgroundColor: Colors.tealAccent.shade700,
                        elevation: 4,
                        onPressed: _handleAcceptIncoming,
                        child: Icon(
                          isVideo ? Icons.videocam : Icons.call,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Accept',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
