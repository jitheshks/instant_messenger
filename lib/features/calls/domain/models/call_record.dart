// lib/features/calls/domain/models/call_record.dart

import 'call_enums.dart';

/// Represents a historical or persisted audio/video call log record.
class CallRecord {
  final String id;
  final String chatId;
  final String callerId;
  final String receiverId;
  final CallType callType;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? peerName;
  final String? peerAvatarUrl;
  final String? peerPhone;
  final bool isGroup;

  const CallRecord({
    required this.id,
    this.chatId = '',
    required this.callerId,
    this.receiverId = '',
    required this.callType,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.createdAt,
    this.updatedAt,
    this.peerName,
    this.peerAvatarUrl,
    this.peerPhone,
    this.isGroup = false,
  });

  /// Whether the call was initiated by another user toward the [currentUserId].
  bool isIncoming(String currentUserId) => callerId != currentUserId;

  /// Whether the call was initiated by the [currentUserId].
  bool isOutgoing(String currentUserId) => callerId == currentUserId;

  /// Whether this was an incoming call that was never answered or accepted.
  bool get isMissed => status == CallStatus.missed;

  /// Whether this call was rejected or declined by the recipient.
  bool get isDeclined =>
      status == CallStatus.declined || status == CallStatus.failed;

  /// Whether this call was cancelled by the caller before being answered.
  bool get isCancelled => status == CallStatus.cancelled;

  /// Whether the call completed normally with media exchange.
  bool get isCompleted => status == CallStatus.ended;

  /// Formatted duration string (e.g., '03:45' or '00:00').
  String get formattedDuration {
    final totalSec = durationSeconds ?? 0;
    if (totalSec <= 0) return '00:00';
    final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSec % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  CallRecord copyWith({
    String? id,
    String? chatId,
    String? callerId,
    String? receiverId,
    CallType? callType,
    CallStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? peerName,
    String? peerAvatarUrl,
    String? peerPhone,
    bool? isGroup,
  }) {
    return CallRecord(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      callerId: callerId ?? this.callerId,
      receiverId: receiverId ?? this.receiverId,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      peerName: peerName ?? this.peerName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      peerPhone: peerPhone ?? this.peerPhone,
      isGroup: isGroup ?? this.isGroup,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'caller_id': callerId,
      'receiver_id': receiverId,
      'call_type': callType.toJson(),
      'status': status.toJson(),
      'started_at': startedAt.toUtc().toIso8601String(),
      if (endedAt != null) 'ended_at': endedAt!.toUtc().toIso8601String(),
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      if (peerName != null) 'peer_name': peerName,
      if (peerAvatarUrl != null) 'peer_avatar_url': peerAvatarUrl,
      if (peerPhone != null) 'peer_phone': peerPhone,
      'is_group': isGroup,
    };
  }

  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      id: map['id'] as String? ?? '',
      chatId: map['chat_id'] as String? ?? map['chatId'] as String? ?? '',
      callerId: map['caller_id'] as String? ?? map['callerId'] as String? ?? '',
      receiverId:
          map['receiver_id'] as String? ?? map['receiverId'] as String? ?? '',
      callType: CallType.fromJson(map['call_type'] as String? ?? map['callType'] as String?),
      status: CallStatus.fromJson(map['status'] as String?),
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'] as String)?.toLocal() ??
                DateTime.now()
          : (map['startedAt'] != null
              ? DateTime.tryParse(map['startedAt'] as String)?.toLocal() ??
                    DateTime.now()
              : DateTime.now()),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)?.toLocal()
          : (map['endedAt'] != null
              ? DateTime.tryParse(map['endedAt'] as String)?.toLocal()
              : null),
      durationSeconds: (map['duration_seconds'] ?? map['durationSeconds']) as int?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toLocal()
          : (map['createdAt'] != null
              ? DateTime.tryParse(map['createdAt'] as String)?.toLocal()
              : null),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toLocal()
          : (map['updatedAt'] != null
              ? DateTime.tryParse(map['updatedAt'] as String)?.toLocal()
              : null),
      peerName: map['peer_name'] as String? ?? map['peerName'] as String?,
      peerAvatarUrl:
          map['peer_avatar_url'] as String? ?? map['peerAvatarUrl'] as String?,
      peerPhone: map['peer_phone'] as String? ?? map['peerPhone'] as String?,
      isGroup: (map['is_group'] as bool?) ?? (map['isGroup'] as bool?) ?? false,
    );
  }

  /// Deserializes a database row from Supabase `public.calls` with optional joined relations.
  factory CallRecord.fromSupabase(
    Map<String, dynamic> map, [
    String? currentUid,
  ]) {
    final callerId = map['caller_id']?.toString() ?? '';
    final isCaller = currentUid != null && callerId == currentUid;

    String receiverId = map['receiver_id']?.toString() ?? '';
    String? peerName;
    String? peerAvatarUrl;
    String? peerPhone;

    // Check joined caller profile
    final callerProfile = map['caller'] is Map ? map['caller'] as Map : null;
    if (!isCaller && callerProfile != null) {
      peerName = callerProfile['display_name'] as String?;
      peerAvatarUrl = callerProfile['avatar_url'] as String?;
      peerPhone = callerProfile['phone_e164'] as String?;
    }

    // Check joined participants
    final participants = map['call_participants'] as List? ?? [];
    for (final p in participants) {
      if (p is Map) {
        final pUid = p['user_id']?.toString() ?? '';
        if (pUid.isNotEmpty && pUid != callerId) {
          if (receiverId.isEmpty) receiverId = pUid;
        }

        if (isCaller && pUid != currentUid) {
          final profile = p['profile'] is Map ? p['profile'] as Map : null;
          if (profile != null) {
            peerName ??= profile['display_name'] as String?;
            peerAvatarUrl ??= profile['avatar_url'] as String?;
            peerPhone ??= profile['phone_e164'] as String?;
          }
        }
      }
    }

    // Status mapping: Supabase calls status strings
    final rawStatus = map['status']?.toString();
    final status = switch (rawStatus?.toLowerCase().trim()) {
      'ringing' => CallStatus.ringing,
      'ongoing' => CallStatus.connected,
      'ended' => CallStatus.ended,
      'rejected' => CallStatus.declined,
      'missed' => CallStatus.missed,
      'cancelled' => CallStatus.cancelled,
      _ => CallStatus.fromJson(rawStatus),
    };

    final rawStartedAt = map['started_at'];
    final startedAt = rawStartedAt is String
        ? DateTime.tryParse(rawStartedAt)?.toLocal() ?? DateTime.now()
        : (rawStartedAt is DateTime ? rawStartedAt.toLocal() : DateTime.now());

    final rawEndedAt = map['ended_at'];
    final endedAt = rawEndedAt is String
        ? DateTime.tryParse(rawEndedAt)?.toLocal()
        : (rawEndedAt is DateTime ? rawEndedAt.toLocal() : null);

    return CallRecord(
      id: map['id']?.toString() ?? '',
      chatId: map['chat_id']?.toString() ?? '',
      callerId: callerId,
      receiverId: receiverId,
      callType: CallType.fromJson(map['call_type']?.toString()),
      status: status,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: map['duration_seconds'] is int
          ? map['duration_seconds'] as int
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())?.toLocal()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())?.toLocal()
          : null,
      peerName: peerName,
      peerAvatarUrl: peerAvatarUrl,
      peerPhone: peerPhone,
      isGroup: map['is_group'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CallRecord &&
        other.id == id &&
        other.chatId == chatId &&
        other.callerId == callerId &&
        other.receiverId == receiverId &&
        other.callType == callType &&
        other.status == status &&
        other.startedAt == startedAt &&
        other.endedAt == endedAt &&
        other.durationSeconds == durationSeconds &&
        other.isGroup == isGroup;
  }

  @override
  int get hashCode => Object.hash(
    id,
    chatId,
    callerId,
    receiverId,
    callType,
    status,
    startedAt,
    endedAt,
    durationSeconds,
    isGroup,
  );

  @override
  String toString() {
    return 'CallRecord(id: $id, callerId: $callerId, receiverId: $receiverId, '
        'type: ${callType.name}, status: ${status.name}, duration: $durationSeconds)';
  }
}
