// lib/features/calls/domain/models/zego_call_models.dart

import 'package:flutter/foundation.dart';
import 'call_enums.dart';

/// Connection state of the user within a ZEGOCLOUD call room.
enum ZegoRoomConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed;

  bool get isConnected => this == ZegoRoomConnectionState.connected;
  bool get isInProgress =>
      this == ZegoRoomConnectionState.connecting ||
      this == ZegoRoomConnectionState.connected ||
      this == ZegoRoomConnectionState.reconnecting;
}

/// Represents an active or connected participant in a ZEGO calling room.
@immutable
class ZegoParticipant {
  final String userId;
  final String userName;
  final String? streamId;
  final bool isLocal;
  final bool hasAudio;
  final bool hasVideo;
  final int? viewId;

  const ZegoParticipant({
    required this.userId,
    required this.userName,
    this.streamId,
    this.isLocal = false,
    this.hasAudio = true,
    this.hasVideo = false,
    this.viewId,
  });

  ZegoParticipant copyWith({
    String? userId,
    String? userName,
    String? streamId,
    bool? isLocal,
    bool? hasAudio,
    bool? hasVideo,
    int? viewId,
    bool clearViewId = false,
    bool clearStreamId = false,
  }) {
    return ZegoParticipant(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      streamId: clearStreamId ? null : (streamId ?? this.streamId),
      isLocal: isLocal ?? this.isLocal,
      hasAudio: hasAudio ?? this.hasAudio,
      hasVideo: hasVideo ?? this.hasVideo,
      viewId: clearViewId ? null : (viewId ?? this.viewId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZegoParticipant &&
        other.userId == userId &&
        other.userName == userName &&
        other.streamId == streamId &&
        other.isLocal == isLocal &&
        other.hasAudio == hasAudio &&
        other.hasVideo == hasVideo &&
        other.viewId == viewId;
  }

  @override
  int get hashCode => Object.hash(
        userId,
        userName,
        streamId,
        isLocal,
        hasAudio,
        hasVideo,
        viewId,
      );

  @override
  String toString() =>
      'ZegoParticipant(userId: $userId, name: $userName, stream: $streamId, audio: $hasAudio, video: $hasVideo, viewId: $viewId)';
}

/// Immutable state representing an active or preparing ZEGOCLOUD media session.
@immutable
class ZegoCallSession {
  final String? callId;
  final String? roomId;
  final CallType callType;
  final ZegoRoomConnectionState connectionState;
  final bool isMicrophoneMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final int? localViewId;
  final String? localStreamId;
  final bool isPublishing;
  final Map<String, ZegoParticipant> participants;
  final int? tokenExpiresAt;
  final String? errorMessage;

  const ZegoCallSession({
    this.callId,
    this.roomId,
    this.callType = CallType.audio,
    this.connectionState = ZegoRoomConnectionState.disconnected,
    this.isMicrophoneMuted = false,
    this.isCameraEnabled = true,
    this.isSpeakerOn = false,
    this.isFrontCamera = true,
    this.localViewId,
    this.localStreamId,
    this.isPublishing = false,
    this.participants = const {},
    this.tokenExpiresAt,
    this.errorMessage,
  });

  /// Factory constructor for an idle, disconnected session.
  factory ZegoCallSession.initial() => const ZegoCallSession();

  bool get isActive =>
      connectionState == ZegoRoomConnectionState.connected ||
      connectionState == ZegoRoomConnectionState.connecting ||
      connectionState == ZegoRoomConnectionState.reconnecting;

  bool get isConnected => connectionState == ZegoRoomConnectionState.connected;

  bool get hasRemoteParticipant =>
      participants.values.any((p) => !p.isLocal);

  bool get isCallEstablished =>
      connectionState == ZegoRoomConnectionState.connected && hasRemoteParticipant;

  List<ZegoParticipant> get remoteParticipants =>
      participants.values.where((p) => !p.isLocal).toList();

  ZegoCallSession copyWith({
    String? callId,
    String? roomId,
    CallType? callType,
    ZegoRoomConnectionState? connectionState,
    bool? isMicrophoneMuted,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? isFrontCamera,
    int? localViewId,
    bool clearLocalViewId = false,
    String? localStreamId,
    bool clearLocalStreamId = false,
    bool? isPublishing,
    Map<String, ZegoParticipant>? participants,
    int? tokenExpiresAt,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ZegoCallSession(
      callId: callId ?? this.callId,
      roomId: roomId ?? this.roomId,
      callType: callType ?? this.callType,
      connectionState: connectionState ?? this.connectionState,
      isMicrophoneMuted: isMicrophoneMuted ?? this.isMicrophoneMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      localViewId: clearLocalViewId ? null : (localViewId ?? this.localViewId),
      localStreamId: clearLocalStreamId ? null : (localStreamId ?? this.localStreamId),
      isPublishing: isPublishing ?? this.isPublishing,
      participants: participants ?? this.participants,
      tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZegoCallSession &&
        other.callId == callId &&
        other.roomId == roomId &&
        other.callType == callType &&
        other.connectionState == connectionState &&
        other.isMicrophoneMuted == isMicrophoneMuted &&
        other.isCameraEnabled == isCameraEnabled &&
        other.isSpeakerOn == isSpeakerOn &&
        other.isFrontCamera == isFrontCamera &&
        other.localViewId == localViewId &&
        other.localStreamId == localStreamId &&
        other.isPublishing == isPublishing &&
        mapEquals(other.participants, participants) &&
        other.tokenExpiresAt == tokenExpiresAt &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        callId,
        roomId,
        callType,
        connectionState,
        isMicrophoneMuted,
        isCameraEnabled,
        isSpeakerOn,
        isFrontCamera,
        localViewId,
        localStreamId,
        isPublishing,
        Object.hashAll(participants.entries),
        tokenExpiresAt,
        errorMessage,
      );

  @override
  String toString() =>
      'ZegoCallSession(callId: $callId, room: $roomId, state: ${connectionState.name}, '
      'micMuted: $isMicrophoneMuted, camEnabled: $isCameraEnabled, speaker: $isSpeakerOn, '
      'participants: ${participants.length}, publishing: $isPublishing)';
}
