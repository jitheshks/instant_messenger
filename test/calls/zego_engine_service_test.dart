// test/calls/zego_engine_service_test.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/data/services/zego_engine_service_impl.dart';
import 'package:instant_messenger/features/calls/data/services/zego_express_adapter.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_call_models.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

class _FakeZegoExpressAdapter implements ZegoExpressAdapter {
  bool isEngineCreated = false;
  ZegoEngineProfile? lastProfile;
  bool isDestroyed = false;

  String? loggedInRoomId;
  ZegoUser? loggedInUser;
  ZegoRoomConfig? lastRoomConfig;
  int loginErrorCodeToReturn = 0;

  String? publishedStreamId;
  bool isPublishing = false;

  final List<String> playingStreams = [];
  bool isPreviewing = false;
  int? previewCanvasViewId;

  bool isMicMuted = false;
  bool isSpeakerMuted = false;
  bool isCameraEnabled = true;
  bool isFrontCamera = true;
  bool isSpeakerphoneOn = false;

  String? renewedToken;
  final List<int> destroyedCanvasViewIds = [];

  // Registered callbacks
  void Function(String roomID, ZegoRoomStateChangedReason reason, int errorCode, Map<String, dynamic> extendedData)?
      onRoomStateChanged;
  void Function(String roomID, ZegoUpdateType updateType, List<ZegoUser> userList)? onRoomUserUpdate;
  void Function(String roomID, ZegoUpdateType updateType, List<ZegoStream> streamList, Map<String, dynamic> extendedData)?
      onRoomStreamUpdate;
  void Function(String roomID, int remainTimeInSecond)? onRoomTokenWillExpire;
  void Function(String streamID, ZegoPublisherState state, int errorCode, Map<String, dynamic> extendedData)?
      onPublisherStateUpdate;
  void Function(String streamID, ZegoPlayerState state, int errorCode, Map<String, dynamic> extendedData)?
      onPlayerStateUpdate;

  @override
  Future<void> createEngineWithProfile(ZegoEngineProfile profile) async {
    isEngineCreated = true;
    lastProfile = profile;
    isDestroyed = false;
  }

  @override
  Future<void> destroyEngine() async {
    isEngineCreated = false;
    isDestroyed = true;
  }

  @override
  Future<ZegoRoomLoginResult> loginRoom(String roomID, ZegoUser user, {ZegoRoomConfig? config}) async {
    loggedInRoomId = roomID;
    loggedInUser = user;
    lastRoomConfig = config;
    return ZegoRoomLoginResult(loginErrorCodeToReturn, {'room_session_id': 'session_123'});
  }

  @override
  Future<ZegoRoomLogoutResult> logoutRoom([String? roomID]) async {
    loggedInRoomId = null;
    return ZegoRoomLogoutResult(0, {});
  }

  @override
  Future<void> renewToken(String roomID, String token) async {
    renewedToken = token;
  }

  @override
  Future<void> startPublishingStream(String streamID, {ZegoPublisherConfig? config, ZegoPublishChannel? channel}) async {
    publishedStreamId = streamID;
    isPublishing = true;
    onPublisherStateUpdate?.call(streamID, ZegoPublisherState.Publishing, 0, {});
  }

  @override
  Future<void> stopPublishingStream({ZegoPublishChannel? channel}) async {
    isPublishing = false;
    if (publishedStreamId != null) {
      onPublisherStateUpdate?.call(publishedStreamId!, ZegoPublisherState.NoPublish, 0, {});
      publishedStreamId = null;
    }
  }

  @override
  Future<void> startPreview({ZegoCanvas? canvas, ZegoPublishChannel? channel}) async {
    isPreviewing = true;
    previewCanvasViewId = canvas?.view;
  }

  @override
  Future<void> stopPreview({ZegoPublishChannel? channel}) async {
    isPreviewing = false;
    previewCanvasViewId = null;
  }

  @override
  Future<void> startPlayingStream(String streamID, {ZegoCanvas? canvas, ZegoPlayerConfig? config}) async {
    if (!playingStreams.contains(streamID)) {
      playingStreams.add(streamID);
    }
    onPlayerStateUpdate?.call(streamID, ZegoPlayerState.Playing, 0, {});
  }

  @override
  Future<void> stopPlayingStream(String streamID) async {
    playingStreams.remove(streamID);
    onPlayerStateUpdate?.call(streamID, ZegoPlayerState.NoPlay, 0, {});
  }

  @override
  Future<void> muteMicrophone(bool mute) async {
    isMicMuted = mute;
  }

  @override
  Future<void> muteSpeaker(bool mute) async {
    isSpeakerMuted = mute;
  }

  @override
  Future<void> enableCamera(bool enable, {ZegoExpNotifyDeviceStateMode? notifyMode, ZegoPublishChannel? channel}) async {
    isCameraEnabled = enable;
  }

  @override
  Future<void> useFrontCamera(bool enable, {ZegoPublishChannel? channel}) async {
    isFrontCamera = enable;
  }

  @override
  Future<void> setAudioRouteToSpeaker(bool defaultToSpeaker) async {
    isSpeakerphoneOn = defaultToSpeaker;
  }

  @override
  Future<Widget?> createCanvasView(Function(int viewID) onViewCreated, {Key? key, dynamic args}) async {
    onViewCreated(1001);
    return const SizedBox(width: 100, height: 100);
  }

  @override
  Future<bool> destroyCanvasView(int viewID) async {
    destroyedCanvasViewIds.add(viewID);
    return true;
  }

  @override
  void registerCallbacks({
    void Function(String roomID, ZegoRoomStateChangedReason reason, int errorCode, Map<String, dynamic> extendedData)?
        onRoomStateChanged,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoUser> userList)? onRoomUserUpdate,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoStream> streamList, Map<String, dynamic> extendedData)?
        onRoomStreamUpdate,
    void Function(String roomID, int remainTimeInSecond)? onRoomTokenWillExpire,
    void Function(String streamID, ZegoPublisherState state, int errorCode, Map<String, dynamic> extendedData)?
        onPublisherStateUpdate,
    void Function(String streamID, ZegoPlayerState state, int errorCode, Map<String, dynamic> extendedData)?
        onPlayerStateUpdate,
  }) {
    this.onRoomStateChanged = onRoomStateChanged;
    this.onRoomUserUpdate = onRoomUserUpdate;
    this.onRoomStreamUpdate = onRoomStreamUpdate;
    this.onRoomTokenWillExpire = onRoomTokenWillExpire;
    this.onPublisherStateUpdate = onPublisherStateUpdate;
    this.onPlayerStateUpdate = onPlayerStateUpdate;
  }

  @override
  void clearCallbacks() {
    onRoomStateChanged = null;
    onRoomUserUpdate = null;
    onRoomStreamUpdate = null;
    onRoomTokenWillExpire = null;
    onPublisherStateUpdate = null;
    onPlayerStateUpdate = null;
  }
}

void main() {
  group('ZegoEngineServiceImpl Tests', () {
    late _FakeZegoExpressAdapter fakeAdapter;
    late ZegoEngineServiceImpl engineService;

    setUp(() {
      fakeAdapter = _FakeZegoExpressAdapter();
      engineService = ZegoEngineServiceImpl(adapter: fakeAdapter);
    });

    tearDown(() async {
      await engineService.dispose();
    });

    test('Engine Initialization creates profile with null appSign (Token04 mode)', () async {
      expect(engineService.isInitialized, isFalse);

      await engineService.initializeEngine(appId: 123456789);

      expect(engineService.isInitialized, isTrue);
      expect(fakeAdapter.isEngineCreated, isTrue);
      expect(fakeAdapter.lastProfile?.appID, 123456789);
      expect(fakeAdapter.lastProfile?.appSign, isNull, reason: 'appSign must be null to enforce server-side Token04');
      expect(fakeAdapter.onRoomStateChanged, isNotNull);
      expect(fakeAdapter.onRoomStreamUpdate, isNotNull);
    });

    test('Repeated initializeEngine with same appId is idempotent', () async {
      await engineService.initializeEngine(appId: 123456789);
      expect(fakeAdapter.isEngineCreated, isTrue);

      // Call again with same appId
      await engineService.initializeEngine(appId: 123456789);
      expect(fakeAdapter.isEngineCreated, isTrue);
      expect(fakeAdapter.isDestroyed, isFalse);
    });

    test('initializeEngine with new appId destroys previous instance first', () async {
      await engineService.initializeEngine(appId: 11111);
      expect(fakeAdapter.lastProfile?.appID, 11111);

      await engineService.initializeEngine(appId: 22222);
      expect(fakeAdapter.lastProfile?.appID, 22222);
    });

    test('joinRoom throws CallsException if engine is not initialized', () async {
      await expectLater(
        engineService.joinRoom(
          callId: 'call-1',
          roomId: 'room-1',
          userId: 'user-1',
          userName: 'Alice',
          token: 'mock-token',
          callType: CallType.audio,
        ),
        throwsA(isA<CallsException>()),
      );
    });

    test('joinRoom validates credentials and rejects empty fields', () async {
      await engineService.initializeEngine(appId: 123456);

      await expectLater(
        engineService.joinRoom(
          callId: 'call-1',
          roomId: '',
          userId: 'user-1',
          userName: 'Alice',
          token: 'token',
          callType: CallType.audio,
        ),
        throwsA(isA<CallsException>()),
      );
    });

    test('joinRoom connects with Token04, configures audio route, and starts publishing stream', () async {
      await engineService.initializeEngine(appId: 123456);

      await engineService.joinRoom(
        callId: 'call-uuid-1',
        roomId: 'room-uuid-1',
        userId: 'user-alice',
        userName: 'Alice',
        token: 'token-04-crypto',
        callType: CallType.video,
      );

      expect(fakeAdapter.loggedInRoomId, 'room-uuid-1');
      expect(fakeAdapter.loggedInUser?.userID, 'user-alice');
      expect(fakeAdapter.loggedInUser?.userName, 'Alice');
      expect(fakeAdapter.lastRoomConfig?.token, 'token-04-crypto');
      expect(fakeAdapter.lastRoomConfig?.isUserStatusNotify, isTrue);

      // Video calls default to speakerphone and camera enabled
      expect(fakeAdapter.isSpeakerphoneOn, isTrue);
      expect(fakeAdapter.isCameraEnabled, isTrue);

      // Stream ID format: <roomId>_<userId>_<type>
      expect(fakeAdapter.publishedStreamId, 'room-uuid-1_user-alice_video');
      expect(engineService.currentSession.isPublishing, isTrue);
      expect(engineService.currentSession.callType, CallType.video);
      expect(engineService.currentSession.participants['user-alice']?.isLocal, isTrue);
    });

    test('joinRoom throws CallsException and marks session failed when ZEGO returns non-zero code', () async {
      await engineService.initializeEngine(appId: 123456);
      fakeAdapter.loginErrorCodeToReturn = 1002001; // ZEGO login failed error code

      await expectLater(
        engineService.joinRoom(
          callId: 'call-err',
          roomId: 'room-err',
          userId: 'user-err',
          userName: 'Bob',
          token: 'invalid-token',
          callType: CallType.audio,
        ),
        throwsA(isA<CallsException>()),
      );

      expect(engineService.currentSession.connectionState, ZegoRoomConnectionState.failed);
      expect(engineService.currentSession.errorMessage, contains('1002001'));
    });

    test('onRoomStateChanged translates ZEGO reasons into ZegoRoomConnectionState', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.audio,
      );

      // Simulate Logined
      fakeAdapter.onRoomStateChanged?.call('room-1', ZegoRoomStateChangedReason.Logined, 0, {});
      expect(engineService.currentSession.connectionState, ZegoRoomConnectionState.connected);

      // Simulate Reconnecting
      fakeAdapter.onRoomStateChanged?.call('room-1', ZegoRoomStateChangedReason.Reconnecting, 0, {});
      expect(engineService.currentSession.connectionState, ZegoRoomConnectionState.reconnecting);

      // Simulate Reconnected
      fakeAdapter.onRoomStateChanged?.call('room-1', ZegoRoomStateChangedReason.Reconnected, 0, {});
      expect(engineService.currentSession.connectionState, ZegoRoomConnectionState.connected);

      // Simulate KickOut
      fakeAdapter.onRoomStateChanged?.call('room-1', ZegoRoomStateChangedReason.KickOut, 0, {});
      expect(engineService.currentSession.connectionState, ZegoRoomConnectionState.disconnected);
    });

    test('onRoomStreamUpdate automatically plays remote audio/video and updates participants', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-local',
        userName: 'LocalUser',
        token: 'token',
        callType: CallType.video,
      );

      // Remote user Bob publishes stream
      final bobStream = ZegoStream(
        ZegoUser('user-bob', 'Bob'),
        'room-1_user-bob_video',
        '',
      );

      fakeAdapter.onRoomStreamUpdate?.call('room-1', ZegoUpdateType.Add, [bobStream], {});

      expect(fakeAdapter.playingStreams, contains('room-1_user-bob_video'));
      expect(engineService.currentSession.participants['user-bob'], isNotNull);
      expect(engineService.currentSession.participants['user-bob']?.streamId, 'room-1_user-bob_video');
      expect(engineService.currentSession.participants['user-bob']?.isLocal, isFalse);

      // Remote user Bob stops stream
      fakeAdapter.onRoomStreamUpdate?.call('room-1', ZegoUpdateType.Delete, [bobStream], {});

      expect(fakeAdapter.playingStreams, isNot(contains('room-1_user-bob_video')));
      expect(engineService.currentSession.participants['user-bob']?.streamId, isNull);
    });

    test('onRoomTokenWillExpire emits remaining seconds to stream', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.audio,
      );

      final expectation = expectLater(
        engineService.tokenWillExpireStream,
        emits(30),
      );

      fakeAdapter.onRoomTokenWillExpire?.call('room-1', 30);
      await expectation;
    });

    test('renewToken forwards token to adapter', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token-initial',
        callType: CallType.audio,
      );

      await engineService.renewToken('token-renewed-xyz');
      expect(fakeAdapter.renewToken, isNotNull);
      expect(fakeAdapter.renewedToken, 'token-renewed-xyz');
    });

    test('muteMicrophone and enableCamera update local state and adapter', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.video,
      );

      // Mute mic
      await engineService.muteMicrophone(true);
      expect(fakeAdapter.isMicMuted, isTrue);
      expect(engineService.currentSession.isMicrophoneMuted, isTrue);
      expect(engineService.currentSession.participants['user-1']?.hasAudio, isFalse);

      // Unmute mic
      await engineService.muteMicrophone(false);
      expect(fakeAdapter.isMicMuted, isFalse);
      expect(engineService.currentSession.isMicrophoneMuted, isFalse);
      expect(engineService.currentSession.participants['user-1']?.hasAudio, isTrue);

      // Disable camera
      await engineService.enableCamera(false);
      expect(fakeAdapter.isCameraEnabled, isFalse);
      expect(engineService.currentSession.isCameraEnabled, isFalse);
      expect(engineService.currentSession.participants['user-1']?.hasVideo, isFalse);
    });

    test('switchCamera toggles between front and rear cameras', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.video,
      );

      expect(engineService.currentSession.isFrontCamera, isTrue);

      await engineService.switchCamera();
      expect(fakeAdapter.isFrontCamera, isFalse);
      expect(engineService.currentSession.isFrontCamera, isFalse);

      await engineService.switchCamera();
      expect(fakeAdapter.isFrontCamera, isTrue);
      expect(engineService.currentSession.isFrontCamera, isTrue);
    });

    test('setSpeakerphoneOn toggles audio output route', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.audio,
      );

      expect(engineService.currentSession.isSpeakerOn, isFalse);

      await engineService.setSpeakerphoneOn(true);
      expect(fakeAdapter.isSpeakerphoneOn, isTrue);
      expect(engineService.currentSession.isSpeakerOn, isTrue);
    });

    test('leaveRoom cleans up all published and playing streams, views, and room session', () async {
      await engineService.initializeEngine(appId: 123456);
      await engineService.joinRoom(
        callId: 'call-1',
        roomId: 'room-1',
        userId: 'user-1',
        userName: 'User1',
        token: 'token',
        callType: CallType.video,
      );

      // Add local preview view
      await engineService.setLocalPreviewView(2001);
      expect(fakeAdapter.isPreviewing, isTrue);

      // Add remote stream
      final charlieStream = ZegoStream(ZegoUser('user-charlie', 'Charlie'), 'room-1_charlie_stream', '');
      fakeAdapter.onRoomStreamUpdate?.call('room-1', ZegoUpdateType.Add, [charlieStream], {});
      await engineService.setRemoteVideoView(streamId: 'room-1_charlie_stream', viewId: 3001);

      expect(fakeAdapter.isPublishing, isTrue);
      expect(fakeAdapter.playingStreams, contains('room-1_charlie_stream'));

      // Leave call room
      await engineService.leaveRoom();

      expect(fakeAdapter.isPublishing, isFalse);
      expect(fakeAdapter.isPreviewing, isFalse);
      expect(fakeAdapter.playingStreams, isEmpty);
      expect(fakeAdapter.loggedInRoomId, isNull);
      expect(fakeAdapter.destroyedCanvasViewIds, containsAll([2001, 3001]));
      expect(engineService.currentSession.isActive, isFalse);
      expect(engineService.currentSession.participants, isEmpty);
    });
  });
}
