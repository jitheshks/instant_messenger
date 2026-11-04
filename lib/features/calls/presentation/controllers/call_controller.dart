// lib/features/calls/presentation/controllers/call_controller.dart

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/zego_engine_service_impl.dart';
import '../../domain/models/call_enums.dart';
import '../../domain/models/zego_call_models.dart';
import '../../domain/repositories/calls_repository.dart';
import '../../domain/services/zego_engine_service.dart';
import '../providers/calls_providers.dart';

/// Central controller orchestrating call lifecycle, permission validation,
/// token acquisition, and media engine synchronization.
class CallController extends Notifier<ZegoCallSession> {
  late final CallsRepository _callsRepository;
  late final ZegoEngineService _engineService;
  late final SupabaseClient _supabase;

  StreamSubscription<ZegoCallSession>? _sessionSubscription;
  StreamSubscription<int>? _tokenExpirySubscription;
  Timer? _heartbeatTimer;

  @override
  ZegoCallSession build() {
    _callsRepository = ref.watch(callsRepositoryProvider);
    _engineService = ref.watch(zegoEngineServiceProvider);
    _supabase = ref.watch(supabaseClientProvider);

    _sessionSubscription?.cancel();
    _sessionSubscription = _engineService.sessionStream.listen((session) {
      state = session;
      _syncHeartbeatLifecycle(session);
    });

    _tokenExpirySubscription?.cancel();
    _tokenExpirySubscription = _engineService.tokenWillExpireStream.listen(
      (remainingSeconds) => _handleTokenRenewal(remainingSeconds),
    );

    ref.onDispose(() {
      _sessionSubscription?.cancel();
      _tokenExpirySubscription?.cancel();
      _stopHeartbeatTimer();
    });

    // Safely detect and recover orphaned active calls left in 'ongoing'
    // after an unexpected app crash or termination.
    unawaited(recoverAbandonedActiveCalls());

    return _engineService.currentSession;
  }

  /// Inspects active calls for the authenticated user and synchronizes call awareness
  /// without destructively terminating sessions on other devices or during network reconnection.
  ///
  /// CRITICAL SAFETY GUARANTEE (Phase 4.1 Hardened):
  /// An idle local RTC engine DOES NOT authorize unilateral client-side termination.
  /// - Active ongoing calls must NOT be terminated with leaveCall (protects multi-device sessions).
  /// - Caller ringing calls must NOT be cancelled with cancelCall (protects in-flight ringing calls).
  /// - Stale ringing calls (> 45s) are safely expired server-authoritative by initiate_call inline timeout.
  Future<void> recoverAbandonedActiveCalls() async {
    // 1. If the local engine is active or in the middle of connecting, the local user is engaged.
    if (_engineService.currentSession.isActive ||
        _engineService.currentSession.connectionState == ZegoRoomConnectionState.connecting) {
      return;
    }

    final currentUid = _supabase.auth.currentUser?.id;
    if (currentUid == null || currentUid.isEmpty) return;

    try {
      final activeCalls = await _callsRepository.fetchActiveCallsForUser();
      for (final call in activeCalls) {
        if (_engineService.currentSession.isActive) break;

        // Non-destructive inspection:
        // Log observed active server state, preserving session integrity across all devices.
        debugPrint(
          '[CallController] Active server call ${call.id} (status: ${call.status}) observed. '
          'Preserving call session integrity without destructive client intervention.',
        );
      }
    } catch (e) {
      debugPrint('[CallController] Non-fatal active calls inspection notice: $e');
    }
  }

  /// Initiates a new outgoing call session.
  Future<bool> startOutgoingCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
    String? localUserName,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      state = state.copyWith(errorMessage: 'Cannot initiate call: user unauthenticated');
      return false;
    }

    // 1. Permission checks
    final micGranted = await PermissionService.ensureMicrophone();
    if (!micGranted) {
      state = state.copyWith(errorMessage: 'Microphone permission is required to place calls.');
      return false;
    }

    if (callType == CallType.video) {
      final camGranted = await PermissionService.ensureCamera();
      if (!camGranted) {
        state = state.copyWith(errorMessage: 'Camera permission is required for video calls.');
        return false;
      }
    }

    try {
      // 2. Atomic backend call initiation
      final initResult = await _callsRepository.initiateCall(
        chatId: chatId,
        callType: callType,
        inviteeIds: inviteeIds,
      );

      // Validate backend business success before extracting identifiers
      final isSuccess = initResult['success'] as bool? ?? false;
      if (!isSuccess) {
        final errorCode = initResult['error'] as String? ?? 'initiation_failed';
        final userMessage = _mapCallErrorToMessage(errorCode);
        throw CallsException(userMessage, errorCode: errorCode);
      }

      return await _proceedWithInitiatedCall(
        result: initResult,
        callType: callType,
        localUserName: localUserName,
        currentUser: currentUser,
      );
    } catch (e) {
      debugPrint('[CallController] Outgoing call initiation failed: $e');
      final message = e is CallsException ? e.message : e.toString();
      await _engineService.leaveRoom();
      state = state.copyWith(errorMessage: message);
      return false;
    }
  }

  Future<bool> _proceedWithInitiatedCall({
    required Map<String, dynamic> result,
    required CallType callType,
    required String? localUserName,
    required User currentUser,
  }) async {
    final callId = result['call_id'] as String?;
    final authoritativeRoomId = result['room_id'] as String?;

    if (callId == null || callId.isEmpty || authoritativeRoomId == null || authoritativeRoomId.isEmpty) {
      throw const CallsException(
        'Backend failed to return authoritative call/room identifiers.',
        errorCode: 'missing_identifiers',
      );
    }

    // Immediate call push dispatch via send-push Edge Function (Stage 2.4).
    try {
      unawaited(
        _supabase.functions.invoke(
          'send-push',
          body: {'call_id': callId},
        ).then((res) {
          if (res.status >= 300) {
            debugPrint(
              '[CallController] Push dispatch warning (status: ${res.status})',
            );
          }
        }).catchError((e) {
          debugPrint(
            '[CallController] Push dispatch network notice: ${e.runtimeType}',
          );
        }),
      );
    } catch (e) {
      debugPrint(
        '[CallController] Push dispatch network notice: ${e.runtimeType}',
      );
    }

    // 3. Cryptographic Token04 retrieval
    final tokenResponse = await _callsRepository.getZegoToken(callId: callId);

    // 4. Engine initialization
    await _engineService.initializeEngine(appId: tokenResponse.appId);

    // 5. Room login and media publishing
    final displayName = localUserName ?? currentUser.phone ?? 'Caller';
    await _engineService.joinRoom(
      callId: callId,
      roomId: authoritativeRoomId,
      userId: currentUser.id,
      userName: displayName,
      token: tokenResponse.token,
      callType: callType,
    );

    return true;
  }

  /// Accepts an incoming call invitation and connects to the media room.
  Future<bool> acceptIncomingCall({
    required String callId,
    required CallType callType,
    String? localUserName,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      state = state.copyWith(errorMessage: 'Cannot accept call: user unauthenticated');
      return false;
    }

    // 1. Permission checks
    final micGranted = await PermissionService.ensureMicrophone();
    if (!micGranted) {
      state = state.copyWith(errorMessage: 'Microphone permission is required to accept calls.');
      return false;
    }

    if (callType == CallType.video) {
      final camGranted = await PermissionService.ensureCamera();
      if (!camGranted) {
        state = state.copyWith(errorMessage: 'Camera permission is required for video calls.');
        return false;
      }
    }

    try {
      // 2. Atomic backend call acceptance
      final acceptResult = await _callsRepository.acceptCall(callId);

      // Validate backend business success before extracting room ID
      final isSuccess = acceptResult['success'] as bool? ?? false;
      if (!isSuccess) {
        final errorCode = acceptResult['error'] as String? ?? 'acceptance_failed';
        final userMessage = _mapCallErrorToMessage(errorCode);
        throw CallsException(userMessage, errorCode: errorCode);
      }

      final authoritativeRoomId = acceptResult['room_id'] as String?;

      if (authoritativeRoomId == null || authoritativeRoomId.isEmpty) {
        throw const CallsException(
          'Backend failed to return authoritative room identifier on acceptance.',
          errorCode: 'missing_room_id',
        );
      }

      // 3. Cryptographic Token04 retrieval
      final tokenResponse = await _callsRepository.getZegoToken(callId: callId);

      // 4. Engine initialization
      await _engineService.initializeEngine(appId: tokenResponse.appId);

      // 5. Room login and media publishing
      final displayName = localUserName ?? currentUser.phone ?? 'Callee';
      await _engineService.joinRoom(
        callId: callId,
        roomId: authoritativeRoomId,
        userId: currentUser.id,
        userName: displayName,
        token: tokenResponse.token,
        callType: callType,
      );

      return true;
    } catch (e) {
      debugPrint('[CallController] Call acceptance failed: $e');
      final message = e is CallsException ? e.message : e.toString();
      await _engineService.leaveRoom();
      state = state.copyWith(errorMessage: message);
      return false;
    }
  }

  /// Safely rejoins an active ongoing call that the user was previously disconnected from.
  Future<bool> rejoinActiveCall({
    required String callId,
    required CallType callType,
    String? localUserName,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      state = state.copyWith(errorMessage: 'Cannot rejoin call: user unauthenticated');
      return false;
    }

    // 1. Permission checks
    final micGranted = await PermissionService.ensureMicrophone();
    if (!micGranted) {
      state = state.copyWith(errorMessage: 'Microphone permission is required to rejoin calls.');
      return false;
    }

    if (callType == CallType.video) {
      final camGranted = await PermissionService.ensureCamera();
      if (!camGranted) {
        state = state.copyWith(errorMessage: 'Camera permission is required for video calls.');
        return false;
      }
    }

    try {
      // 2. Atomic backend call rejoin
      final rejoinResult = await _callsRepository.rejoinCall(callId);

      final isSuccess = rejoinResult['success'] as bool? ?? false;
      if (!isSuccess) {
        final errorCode = rejoinResult['error'] as String? ?? 'rejoin_failed';
        final userMessage = _mapCallErrorToMessage(errorCode);
        throw CallsException(userMessage, errorCode: errorCode);
      }

      final authoritativeRoomId = rejoinResult['room_id'] as String?;
      if (authoritativeRoomId == null || authoritativeRoomId.isEmpty) {
        throw const CallsException(
          'Backend failed to return authoritative room identifier on rejoin.',
          errorCode: 'missing_room_id',
        );
      }

      // 3. Cryptographic Token04 retrieval
      final tokenResponse = await _callsRepository.getZegoToken(callId: callId);

      // 4. Engine initialization
      await _engineService.initializeEngine(appId: tokenResponse.appId);

      // 5. Room login and media publishing
      final displayName = localUserName ?? currentUser.phone ?? 'Participant';
      await _engineService.joinRoom(
        callId: callId,
        roomId: authoritativeRoomId,
        userId: currentUser.id,
        userName: displayName,
        token: tokenResponse.token,
        callType: callType,
      );

      return true;
    } catch (e) {
      debugPrint('[CallController] Rejoin call failed: $e');
      final message = e is CallsException ? e.message : e.toString();
      await _engineService.leaveRoom();
      state = state.copyWith(errorMessage: message);
      return false;
    }
  }

  /// Rejects an incoming call invitation on the backend.
  Future<void> rejectIncomingCall(String callId) async {
    try {
      await _callsRepository.rejectCall(callId);
    } catch (e) {
      debugPrint('[CallController] Rejection error: $e');
    }
  }

  /// Terminates the current call session locally and notifies the backend.
  Future<void> endCall() async {
    _stopHeartbeatTimer();
    final currentCallId = state.callId;
    final currentUid = _supabase.auth.currentUser?.id;
    final isCaller = state.participants[currentUid]?.isLocal == true &&
        state.participants.length <= 1;

    try {
      await _engineService.leaveRoom();

      if (currentCallId != null && currentCallId.isNotEmpty) {
        if (isCaller && state.connectionState != ZegoRoomConnectionState.connected) {
          await _callsRepository.cancelCall(currentCallId);
        } else {
          await _callsRepository.leaveCall(currentCallId);
        }
      }
    } catch (e) {
      debugPrint('[CallController] Error terminating call session: $e');
    }
  }

  /// Manages heartbeat lifecycle synchronized strictly to RTC connection state.
  ///
  /// Requirement A2: Only start periodic heartbeats when RTC is actually
  /// connected (ZegoRoomConnectionState.connected). Distinguishes invitation
  /// acceptance from genuine media channel connection.
  void _syncHeartbeatLifecycle(ZegoCallSession session) {
    final isRtcConnected =
        session.connectionState == ZegoRoomConnectionState.connected;
    final callId = session.callId;

    if (isRtcConnected && callId != null && callId.isNotEmpty && session.isActive) {
      if (_heartbeatTimer == null || !_heartbeatTimer!.isActive) {
        _startHeartbeatTimer(callId);
      }
    } else {
      _stopHeartbeatTimer();
    }
  }

  void _startHeartbeatTimer(String callId) {
    _stopHeartbeatTimer();
    // Immediate heartbeat pulse upon establishing RTC connection
    unawaited(_sendHeartbeat(callId));
    // Periodic pulse every 25s (well below the 90s server timeout)
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_sendHeartbeat(callId));
    });
  }

  Future<void> _sendHeartbeat(String callId) async {
    try {
      final res = await _callsRepository.heartbeatCall(callId);
      if (res['success'] == false &&
          (res['error'] == 'call_ended' || res['error'] == 'call_not_ongoing')) {
        // Stale heartbeat guard: only terminate local session if the current active
        // call still corresponds to the call that emitted this heartbeat.
        if (state.callId == callId && state.isActive) {
          debugPrint(
            '[CallController] Heartbeat received call_ended/call_not_ongoing; terminating local session for call $callId',
          );
          await endCall();
        } else {
          debugPrint(
            '[CallController] Ignoring stale heartbeat error for past call $callId (current: ${state.callId}, active: ${state.isActive})',
          );
        }
      }
    } catch (e) {
      debugPrint('[CallController] Heartbeat send notice: $e');
    }
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Toggles local microphone state.
  Future<void> toggleMicrophone() async {
    final newMute = !state.isMicrophoneMuted;
    await _engineService.muteMicrophone(newMute);
  }

  /// Toggles local camera state.
  Future<void> toggleCamera() async {
    final newEnable = !state.isCameraEnabled;
    await _engineService.enableCamera(newEnable);
  }

  /// Switches between front and rear cameras.
  Future<void> switchCamera() async {
    await _engineService.switchCamera();
  }

  /// Toggles audio output between speakerphone and earpiece/default.
  Future<void> toggleSpeaker() async {
    final newSpeaker = !state.isSpeakerOn;
    await _engineService.setSpeakerphoneOn(newSpeaker);
  }

  /// Sets or clears the local video preview canvas view.
  Future<void> setLocalPreviewView(int? viewId) async {
    await _engineService.setLocalPreviewView(viewId);
  }

  /// Binds or unbinds a remote stream to a video canvas view.
  Future<void> setRemoteVideoView(String streamId, int? viewId) async {
    await _engineService.setRemoteVideoView(streamId: streamId, viewId: viewId);
  }

  /// Invites additional participants to an active call.
  Future<bool> inviteParticipants(List<String> inviteeIds) async {
    final callId = state.callId;
    if (callId == null || callId.isEmpty || inviteeIds.isEmpty) return false;

    try {
      final res = await _callsRepository.inviteToCall(
        callId: callId,
        inviteeIds: inviteeIds,
      );
      return res['success'] == true;
    } catch (e) {
      debugPrint('[CallController] Invite error: $e');
      return false;
    }
  }

  /// Creates a native video canvas widget.
  Future<Widget?> createVideoView(Function(int viewID) onViewCreated, {Key? key, dynamic args}) {
    final service = _engineService;
    if (service is ZegoEngineServiceImpl) {
      return service.createCanvasView(onViewCreated, key: key, args: args);
    }
    return Future.value(null);
  }

  /// Destroys a native video canvas.
  Future<bool> destroyVideoView(int viewID) {
    final service = _engineService;
    if (service is ZegoEngineServiceImpl) {
      return service.destroyCanvasView(viewID);
    }
    return Future.value(false);
  }

  /// Handles automatic token renewal when approaching expiration.
  Future<void> _handleTokenRenewal(int remainingSeconds) async {
    final callId = state.callId;
    if (callId == null || callId.isEmpty) return;

    debugPrint('[CallController] Handling automatic token renewal (remaining: ${remainingSeconds}s)');
    try {
      final newTokenResponse = await _callsRepository.getZegoToken(callId: callId);
      await _engineService.renewToken(newTokenResponse.token);
      state = state.copyWith(tokenExpiresAt: newTokenResponse.expiresAt);
      debugPrint('[CallController] Successfully renewed ZEGOCLOUD Token04');
    } catch (e) {
      debugPrint('[CallController] Token renewal failed: $e');
    }
  }

  /// Maps raw backend RPC error codes to user-friendly error messages.
  static String _mapCallErrorToMessage(String errorCode) {
    switch (errorCode) {
      case 'call_in_progress':
        return 'Another call is already in progress in this chat.';
      case 'call_timed_out':
        return 'This call has timed out.';
      case 'call_terminated':
        return 'This call has already ended.';
      case 'invitation_rejected':
        return 'The call invitation was declined.';
      case 'invitation_cancelled':
        return 'The call was cancelled by the caller.';
      case 'invitation_left':
        return 'You have already left this call.';
      case 'invitation_missed':
        return 'This call invitation was missed.';
      case 'cannot_cancel_active_or_ended_call':
        return 'Cannot cancel call: the call is already active or ended.';
      case 'invalid_status_for_rejection':
        return 'Cannot decline call: invitation is no longer pending.';
      case 'invalid_status_to_leave':
        return 'Cannot leave call: you are not currently in this call.';
      case 'invalid_status_for_rejoin':
        return 'Cannot rejoin call: participant is not eligible to rejoin.';
      default:
        if (errorCode.startsWith('cannot_rejoin_call_status_')) {
          return 'Cannot rejoin call: call is no longer active.';
        }
        return 'Call operation failed: $errorCode';
    }
  }
}
