// lib/features/calls/domain/models/call_rpc_result.dart

import 'package:flutter/foundation.dart';

/// Typed representation of standardized backend calling RPC responses.
@immutable
class CallRpcResult {
  final bool success;
  final String? callId;
  final String? roomId;
  final String? callType;
  final String? status;
  final String? errorCode;
  final String? existingCallId;
  final int? processedCount;
  final Map<String, dynamic> raw;

  const CallRpcResult({
    required this.success,
    this.callId,
    this.roomId,
    this.callType,
    this.status,
    this.errorCode,
    this.existingCallId,
    this.processedCount,
    this.raw = const {},
  });

  factory CallRpcResult.fromMap(Map<String, dynamic> map) {
    return CallRpcResult(
      success: map['success'] as bool? ?? false,
      callId: map['call_id'] as String?,
      roomId: map['room_id'] as String?,
      callType: map['call_type'] as String?,
      status: map['status'] as String?,
      errorCode: map['error'] as String?,
      existingCallId: map['existing_call_id'] as String?,
      processedCount: map['processed_count'] as int?,
      raw: map,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CallRpcResult &&
        other.success == success &&
        other.callId == callId &&
        other.roomId == roomId &&
        other.callType == callType &&
        other.status == status &&
        other.errorCode == errorCode &&
        other.existingCallId == existingCallId &&
        other.processedCount == processedCount;
  }

  @override
  int get hashCode => Object.hash(
        success,
        callId,
        roomId,
        callType,
        status,
        errorCode,
        existingCallId,
        processedCount,
      );

  @override
  String toString() =>
      'CallRpcResult(success: $success, callId: $callId, error: $errorCode, status: $status)';
}
