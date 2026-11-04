// lib/features/calls/data/services/zego_engine_service_impl.dart

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

import '../../domain/models/call_enums.dart';
import '../../domain/models/zego_call_models.dart';
import '../../domain/repositories/calls_repository.dart';
import '../../domain/services/zego_engine_service.dart';
import 'zego_express_adapter.dart';

/// Production implementation of [ZegoEngineService] controlling ZEGOCLOUD Express SDK.
class ZegoEngineServiceImpl implements ZegoEngineService {
  final ZegoExpressAdapter _adapter;

  bool _isInitialized = false;
  int? _appId;
  String? _currentUserId;

  ZegoCallSession _currentSession = ZegoCallSession.initial();
  final StreamController<ZegoCallSession> _sessionStreamController =
      StreamController<ZegoCallSession>.broadcast();
  final StreamController<int> _tokenWillExpireController =
      StreamController<int>.broadcast();

  ZegoEngineServiceImpl({ZegoExpressAdapter? adapter})
      : _adapter = adapter ?? DefaultZegoExpressAdapter();

  @override
  bool get isInitialized => _isInitialized;

  @override
  ZegoCallSession get currentSession => _currentSession;

  @override
  Stream<ZegoCallSession> get sessionStream => _sessionStreamController.stream;

  @override
  Stream<int> get tokenWillExpireStream => _tokenWillExpireController.stream;

  void _updateSession(ZegoCallSession session) {
    _currentSession = session;
    if (!_sessionStreamController.isClosed) {
      _sessionStreamController.add(session);
    }
  }

  @override
  Future<void> initializeEngine({
    required int appId,
    ZegoCallScenario scenario = ZegoCallScenario.standardCall,
  }) async {
    if (_isInitialized && _appId == appId) {
      debugPrint('[ZegoEngineService] Engine already initialized with appId: $appId');
      return;
    }

    if (_isInitialized && _appId != appId) {
      await destroyEngine();
    }

    final zegoScenario = switch (scenario) {
      ZegoCallScenario.standardCall => ZegoScenario.Default,
      ZegoCallScenario.highQualityAudio => ZegoScenario.StandardVoiceCall,
    };

    // Initialize with appSign = null (Token04 server-side authentication enforced)
    final profile = ZegoEngineProfile(
      appId,
      zegoScenario,
      appSign: null,
      enablePlatformView: false,
    );

    debugPrint('[ZegoEngineService] Initializing ZegoExpressEngine (appId: $appId, scenario: ${zegoScenario.name})');
    await _adapter.createEngineWithProfile(profile);

    _adapter.registerCallbacks(
      onRoomStateChanged: _handleRoomStateChanged,
      onRoomUserUpdate: _handleRoomUserUpdate,
      onRoomStreamUpdate: _handleRoomStreamUpdate,
      onRoomTokenWillExpire: _handleRoomTokenWillExpire,
      onPublisherStateUpdate: _handlePublisherStateUpdate,
      onPlayerStateUpdate: _handlePlayerStateUpdate,
    );

    _isInitialized = true;
    _appId = appId;
  }

  @override
  Future<void> destroyEngine() async {
    if (!_isInitialized) return;

    debugPrint('[ZegoEngineService] Destroying ZegoExpressEngine');
    if (_currentSession.isActive) {
      await leaveRoom();
    }

    _adapter.clearCallbacks();
    await _adapter.destroyEngine();

    _isInitialized = false;
    _appId = null;
    _currentUserId = null;
  }

  @override
  Future<void> joinRoom({
    required String callId,
    required String roomId,
    required String userId,
    required String userName,
    required String token,
    required CallType callType,
  }) async {
    if (!_isInitialized) {
      throw const CallsException(
        'Cannot join call room: ZEGO Engine is not initialized.',
        statusCode: 500,
      );
    }

    if (roomId.trim().isEmpty || userId.trim().isEmpty || token.trim().isEmpty) {
      throw const CallsException(
        'Invalid room credentials: roomId, userId, and token must not be empty.',
        statusCode: 400,
      );
    }

    _currentUserId = userId;

    final initialLocalParticipant = ZegoParticipant(
      userId: userId,
      userName: userName,
      isLocal: true,
      hasAudio: true,
      hasVideo: callType == CallType.video,
    );

    final isVideo = callType == CallType.video;
    _updateSession(_currentSession.copyWith(
      callId: callId,
      roomId: roomId,
      callType: callType,
      connectionState: ZegoRoomConnectionState.connecting,
      isMicrophoneMuted: false,
      isCameraEnabled: isVideo,
      isSpeakerOn: isVideo, // Video calls default to speakerphone; audio calls to earpiece
      isFrontCamera: true,
      participants: {userId: initialLocalParticipant},
      clearErrorMessage: true,
    ));

    // Audio routing
    await _adapter.setAudioRouteToSpeaker(isVideo);

    final zegoUser = ZegoUser(userId, userName);
    final zegoConfig = ZegoRoomConfig(0, true, token);

    debugPrint('[ZegoEngineService] Logging in to room $roomId for user $userId (callId: $callId)');
    final loginResult = await _adapter.loginRoom(roomId, zegoUser, config: zegoConfig);

    if (loginResult.errorCode != 0) {
      final errorMsg = 'Failed to login to room $roomId (code: ${loginResult.errorCode})';
      debugPrint('[ZegoEngineService] $errorMsg');
      _updateSession(_currentSession.copyWith(
        connectionState: ZegoRoomConnectionState.failed,
        errorMessage: errorMsg,
      ));
      throw CallsException(errorMsg, statusCode: loginResult.errorCode);
    }

    // Media stream identifier: <roomId>_<userId>_<audio|video>
    final streamId = '${roomId}_${userId}_${callType.name}';

    // Camera hardware activation
    await _adapter.enableCamera(isVideo);
    await _adapter.useFrontCamera(true);

    // Publish local media stream
    debugPrint('[ZegoEngineService] Starting stream publishing: $streamId');
    await _adapter.startPublishingStream(streamId);

    _updateSession(_currentSession.copyWith(
      localStreamId: streamId,
      isPublishing: true,
      participants: {
        userId: initialLocalParticipant.copyWith(streamId: streamId),
      },
    ));
  }

  @override
  Future<void> leaveRoom() async {
    final roomId = _currentSession.roomId;
    debugPrint('[ZegoEngineService] Leaving call room: $roomId');

    try {
      if (_currentSession.isPublishing) {
        await _adapter.stopPublishingStream();
      }
      if (_currentSession.localViewId != null) {
        await _adapter.stopPreview();
        await _adapter.destroyCanvasView(_currentSession.localViewId!);
      }

      // Stop playing all remote streams and destroy their canvases
      for (final participant in _currentSession.remoteParticipants) {
        if (participant.streamId != null) {
          await _adapter.stopPlayingStream(participant.streamId!);
        }
        if (participant.viewId != null) {
          await _adapter.destroyCanvasView(participant.viewId!);
        }
      }

      if (roomId != null && roomId.isNotEmpty) {
        await _adapter.logoutRoom(roomId);
      }
    } catch (e) {
      debugPrint('[ZegoEngineService] Non-fatal error during room departure: $e');
    } finally {
      _currentUserId = null;
      _updateSession(ZegoCallSession.initial());
    }
  }

  @override
  Future<void> muteMicrophone(bool mute) async {
    await _adapter.muteMicrophone(mute);

    final localUid = _currentUserId;
    final updatedParticipants = Map<String, ZegoParticipant>.from(_currentSession.participants);
    if (localUid != null && updatedParticipants.containsKey(localUid)) {
      updatedParticipants[localUid] = updatedParticipants[localUid]!.copyWith(hasAudio: !mute);
    }

    _updateSession(_currentSession.copyWith(
      isMicrophoneMuted: mute,
      participants: updatedParticipants,
    ));
  }

  @override
  Future<void> enableCamera(bool enable) async {
    await _adapter.enableCamera(enable);

    final localUid = _currentUserId;
    final updatedParticipants = Map<String, ZegoParticipant>.from(_currentSession.participants);
    if (localUid != null && updatedParticipants.containsKey(localUid)) {
      updatedParticipants[localUid] = updatedParticipants[localUid]!.copyWith(hasVideo: enable);
    }

    _updateSession(_currentSession.copyWith(
      isCameraEnabled: enable,
      participants: updatedParticipants,
    ));
  }

  @override
  Future<void> switchCamera() async {
    final newFront = !_currentSession.isFrontCamera;
    await _adapter.useFrontCamera(newFront);
    _updateSession(_currentSession.copyWith(isFrontCamera: newFront));
  }

  @override
  Future<void> setSpeakerphoneOn(bool enable) async {
    await _adapter.setAudioRouteToSpeaker(enable);
    _updateSession(_currentSession.copyWith(isSpeakerOn: enable));
  }

  @override
  Future<void> renewToken(String token) async {
    final roomId = _currentSession.roomId;
    if (roomId == null || roomId.isEmpty) return;

    debugPrint('[ZegoEngineService] Renewing Token04 for room $roomId');
    await _adapter.renewToken(roomId, token);
  }

  @override
  Future<void> setLocalPreviewView(int? viewId) async {
    if (viewId != null) {
      await _adapter.startPreview(canvas: ZegoCanvas(viewId));
      _updateSession(_currentSession.copyWith(localViewId: viewId));
    } else {
      await _adapter.stopPreview();
      _updateSession(_currentSession.copyWith(clearLocalViewId: true));
    }
  }

  @override
  Future<void> setRemoteVideoView({
    required String streamId,
    int? viewId,
  }) async {
    final updatedParticipants = Map<String, ZegoParticipant>.from(_currentSession.participants);
    String? matchedUid;

    for (final entry in updatedParticipants.entries) {
      if (entry.value.streamId == streamId) {
        matchedUid = entry.key;
        break;
      }
    }

    if (viewId != null) {
      await _adapter.startPlayingStream(streamId, canvas: ZegoCanvas(viewId));
      if (matchedUid != null) {
        updatedParticipants[matchedUid] = updatedParticipants[matchedUid]!.copyWith(viewId: viewId);
      }
    } else {
      // Audio-only playback
      await _adapter.startPlayingStream(streamId, canvas: null);
      if (matchedUid != null) {
        updatedParticipants[matchedUid] = updatedParticipants[matchedUid]!.copyWith(clearViewId: true);
      }
    }

    _updateSession(_currentSession.copyWith(participants: updatedParticipants));
  }

  /// Creates a canvas view widget for rendering local or remote video.
  Future<Widget?> createCanvasView(Function(int viewID) onViewCreated, {Key? key, dynamic args}) {
    return _adapter.createCanvasView(onViewCreated, key: key, args: args);
  }

  /// Destroys a canvas view allocated natively.
  Future<bool> destroyCanvasView(int viewID) {
    return _adapter.destroyCanvasView(viewID);
  }

  @override
  Future<void> dispose() async {
    await destroyEngine();
    await _sessionStreamController.close();
    await _tokenWillExpireController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal Event Handlers
  // ---------------------------------------------------------------------------

  void _handleRoomStateChanged(
    String roomID,
    ZegoRoomStateChangedReason reason,
    int errorCode,
    Map<String, dynamic> extendedData,
  ) {
    if (roomID != _currentSession.roomId) return;

    debugPrint('[ZegoEngineService] Room state changed: ${reason.name} (code: $errorCode)');

    final newState = switch (reason) {
      ZegoRoomStateChangedReason.Logining => ZegoRoomConnectionState.connecting,
      ZegoRoomStateChangedReason.Logined => ZegoRoomConnectionState.connected,
      ZegoRoomStateChangedReason.LoginFailed => ZegoRoomConnectionState.failed,
      ZegoRoomStateChangedReason.Reconnecting => ZegoRoomConnectionState.reconnecting,
      ZegoRoomStateChangedReason.Reconnected => ZegoRoomConnectionState.connected,
      ZegoRoomStateChangedReason.ReconnectFailed => ZegoRoomConnectionState.failed,
      ZegoRoomStateChangedReason.KickOut => ZegoRoomConnectionState.disconnected,
      ZegoRoomStateChangedReason.Logout => ZegoRoomConnectionState.disconnected,
      ZegoRoomStateChangedReason.LogoutFailed => ZegoRoomConnectionState.failed,
    };

    String? error;
    if (errorCode != 0 && (newState == ZegoRoomConnectionState.failed)) {
      error = 'Room error: ${reason.name} (code $errorCode)';
    }

    _updateSession(_currentSession.copyWith(
      connectionState: newState,
      errorMessage: error,
      clearErrorMessage: error == null,
    ));
  }

  void _handleRoomUserUpdate(
    String roomID,
    ZegoUpdateType updateType,
    List<ZegoUser> userList,
  ) {
    if (roomID != _currentSession.roomId) return;

    final updatedParticipants = Map<String, ZegoParticipant>.from(_currentSession.participants);

    for (final user in userList) {
      final uid = user.userID;
      if (updateType == ZegoUpdateType.Add) {
        if (!updatedParticipants.containsKey(uid)) {
          updatedParticipants[uid] = ZegoParticipant(
            userId: uid,
            userName: user.userName,
            isLocal: uid == _currentUserId,
          );
        }
      } else if (updateType == ZegoUpdateType.Delete) {
        if (uid != _currentUserId) {
          updatedParticipants.remove(uid);
        }
      }
    }

    _updateSession(_currentSession.copyWith(participants: updatedParticipants));
  }

  void _handleRoomStreamUpdate(
    String roomID,
    ZegoUpdateType updateType,
    List<ZegoStream> streamList,
    Map<String, dynamic> extendedData,
  ) {
    if (roomID != _currentSession.roomId) return;

    final updatedParticipants = Map<String, ZegoParticipant>.from(_currentSession.participants);

    for (final stream in streamList) {
      final uid = stream.user.userID;
      final isLocal = uid == _currentUserId;

      if (updateType == ZegoUpdateType.Add) {
        final existing = updatedParticipants[uid] ??
            ZegoParticipant(
              userId: uid,
              userName: stream.user.userName,
              isLocal: isLocal,
            );

        updatedParticipants[uid] = existing.copyWith(
          streamId: stream.streamID,
          hasAudio: true,
          hasVideo: _currentSession.callType == CallType.video,
        );

        // Auto-play remote stream audio
        if (!isLocal) {
          debugPrint('[ZegoEngineService] Auto-playing remote stream: ${stream.streamID}');
          _adapter.startPlayingStream(stream.streamID);
        }
      } else if (updateType == ZegoUpdateType.Delete) {
        if (!isLocal) {
          debugPrint('[ZegoEngineService] Stopping remote stream: ${stream.streamID}');
          _adapter.stopPlayingStream(stream.streamID);
        }
        final existing = updatedParticipants[uid];
        if (existing != null) {
          updatedParticipants[uid] = existing.copyWith(
            clearStreamId: true,
            clearViewId: true,
          );
        }
      }
    }

    _updateSession(_currentSession.copyWith(participants: updatedParticipants));
  }

  void _handleRoomTokenWillExpire(String roomID, int remainTimeInSecond) {
    if (roomID != _currentSession.roomId) return;
    debugPrint('[ZegoEngineService] Token will expire in $remainTimeInSecond seconds for room $roomID');
    if (!_tokenWillExpireController.isClosed) {
      _tokenWillExpireController.add(remainTimeInSecond);
    }
  }

  void _handlePublisherStateUpdate(
    String streamID,
    ZegoPublisherState state,
    int errorCode,
    Map<String, dynamic> extendedData,
  ) {
    final isPublishing = state == ZegoPublisherState.Publishing;
    debugPrint('[ZegoEngineService] Publisher state update: ${state.name} (code: $errorCode)');
    _updateSession(_currentSession.copyWith(isPublishing: isPublishing));
  }

  void _handlePlayerStateUpdate(
    String streamID,
    ZegoPlayerState state,
    int errorCode,
    Map<String, dynamic> extendedData,
  ) {
    debugPrint('[ZegoEngineService] Player state update for stream $streamID: ${state.name} (code: $errorCode)');
  }
}
