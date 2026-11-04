// lib/features/calls/domain/repositories/calls_repository.dart

import '../models/call_enums.dart';
import '../models/call_record.dart';
import '../models/zego_token_response.dart';

/// Exceptions thrown during calling operations or token requests.
class CallsException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;
  final Object? cause;

  const CallsException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.cause,
  });

  @override
  String toString() =>
      'CallsException: $message${errorCode != null ? ' [code: $errorCode]' : ''}${statusCode != null ? ' (status: $statusCode)' : ''}';
}

/// Abstract contract for calling services, token retrieval, and call records.
abstract class CallsRepository {
  /// Requests a secure ZEGOCLOUD Token04 from the backend for the currently
  /// authenticated user.
  ///
  /// Throws [CallsException] if unauthenticated, if backend returns an error,
  /// or if response parsing fails.
  Future<ZegoTokenResponse> getZegoToken({
    String? callId,
    String? roomId,
    int? effectiveTimeInSeconds,
    CallType? callType,
  });

  /// Initiates a new audio or video call with atomic concurrency locking.
  Future<Map<String, dynamic>> initiateCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
  });

  /// Accepts an incoming call invitation.
  Future<Map<String, dynamic>> acceptCall(String callId);

  /// Rejects an incoming call invitation.
  Future<Map<String, dynamic>> rejectCall(String callId);

  /// Cancels an outgoing call before it is answered.
  Future<Map<String, dynamic>> cancelCall(String callId);

  /// Leaves an ongoing or ringing call.
  Future<Map<String, dynamic>> leaveCall(String callId);

  /// Invites additional chat members to an ongoing group call.
  Future<Map<String, dynamic>> inviteToCall({
    required String callId,
    required List<String> inviteeIds,
  });

  /// Rejoins an ongoing call that was previously left.
  Future<Map<String, dynamic>> rejoinCall(String callId);

  /// Pulses a participant heartbeat to affirm active attendance in an ongoing call.
  Future<Map<String, dynamic>> heartbeatCall(String callId) async =>
      {'success': true};

  /// Triggers timeout transition for a ringing call (service_role or automated runner).
  Future<Map<String, dynamic>> timeoutCall(String callId);

  /// Fetches an individual call record by ID from the backend.
  Future<CallRecord?> getCallById(String callId) async => null;

  /// Fetches paginated historical call records for the authenticated user.
  Future<List<CallRecord>> fetchCallHistory({int limit = 50, int offset = 0}) async =>
      const [];

  /// Fetches active calls (status in 'ringing', 'ongoing') for the current user.
  Future<List<CallRecord>> fetchActiveCallsForUser() async => const [];

  /// Attaches or updates the active connection manager for socket lifecycle coordination.
  void attachConnectionManager(dynamic connectionManager) {}

  /// Watches realtime updates to the user's call history.
  Stream<List<CallRecord>> watchCallHistory() => const Stream.empty();

  /// Fetches historical call records for a specific chat conversation.
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async => const [];

  /// Watches realtime updates to calls within a specific chat conversation.
  Stream<List<CallRecord>> watchCallsForChat(String chatId) => const Stream.empty();
}
