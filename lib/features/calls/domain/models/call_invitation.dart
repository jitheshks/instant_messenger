// lib/features/calls/domain/models/call_invitation.dart

import 'call_enums.dart';

/// Minimal domain representation of an incoming or outgoing call invitation.
class CallInvitation {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String receiverId;
  final CallType callType;
  final DateTime sentAt;

  const CallInvitation({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.receiverId,
    required this.callType,
    required this.sentAt,
  });

  CallInvitation copyWith({
    String? callId,
    String? callerId,
    String? callerName,
    String? callerAvatar,
    String? receiverId,
    CallType? callType,
    DateTime? sentAt,
  }) {
    return CallInvitation(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      receiverId: receiverId ?? this.receiverId,
      callType: callType ?? this.callType,
      sentAt: sentAt ?? this.sentAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'call_id': callId,
      'caller_id': callerId,
      'caller_name': callerName,
      if (callerAvatar != null) 'caller_avatar': callerAvatar,
      'receiver_id': receiverId,
      'call_type': callType.toJson(),
      'sent_at': sentAt.toUtc().toIso8601String(),
    };
  }

  factory CallInvitation.fromMap(Map<String, dynamic> map) {
    return CallInvitation(
      callId: map['call_id'] as String? ?? '',
      callerId: map['caller_id'] as String? ?? '',
      callerName: map['caller_name'] as String? ?? '',
      callerAvatar: map['caller_avatar'] as String?,
      receiverId: map['receiver_id'] as String? ?? '',
      callType: CallType.fromJson(map['call_type'] as String?),
      sentAt: map['sent_at'] != null
          ? DateTime.tryParse(map['sent_at'] as String)?.toLocal() ??
                DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CallInvitation &&
        other.callId == callId &&
        other.callerId == callerId &&
        other.callerName == callerName &&
        other.callerAvatar == callerAvatar &&
        other.receiverId == receiverId &&
        other.callType == callType &&
        other.sentAt == sentAt;
  }

  @override
  int get hashCode => Object.hash(
    callId,
    callerId,
    callerName,
    callerAvatar,
    receiverId,
    callType,
    sentAt,
  );

  @override
  String toString() {
    return 'CallInvitation(callId: $callId, callerId: $callerId, '
        'receiverId: $receiverId, type: ${callType.name})';
  }
}
