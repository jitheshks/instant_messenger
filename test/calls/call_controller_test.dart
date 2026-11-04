// test/calls/call_controller_test.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_call_models.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/services/zego_engine_service.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockGoTrueClient implements GoTrueClient {
  User? mockUser;
  _MockGoTrueClient({this.mockUser});

  @override
  User? get currentUser => mockUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFunctionsClient implements FunctionsClient {
  final List<Map<String, dynamic>> invocations = [];
  Future<FunctionResponse> Function(String functionName, Map<String, dynamic>? body)? handler;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) async {
    invocations.add({
      'functionName': functionName,
      'headers': headers,
      'body': body,
      'method': method,
    });
    if (handler != null) {
      return handler!(functionName, body is Map<String, dynamic> ? body : null);
    }
    return const FunctionResponse(status: 200, data: {'success': true});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSupabaseClient implements SupabaseClient {
  final _MockGoTrueClient _auth;
  final _MockFunctionsClient _functions;

  _MockSupabaseClient({User? user, _MockFunctionsClient? functions})
      : _auth = _MockGoTrueClient(mockUser: user),
        _functions = functions ?? _MockFunctionsClient();

  @override
  GoTrueClient get auth => _auth;

  @override
  FunctionsClient get functions => _functions;

  _MockFunctionsClient get mockFunctions => _functions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockCallsRepository implements CallsRepository {
  bool initiateCalled = false;
  bool acceptCalled = false;
  bool rejectCalled = false;
  bool cancelCalled = false;
  bool leaveCalled = false;
  bool getTokenCalled = false;
  String? lastCallId;

  Map<String, dynamic> initiateReturn = {
    'success': true,
    'call_id': 'call-1234',
    'room_id': 'room-1234',
    'call_type': 'audio',
    'status': 'ringing',
  };

  Map<String, dynamic> acceptReturn = {
    'success': true,
    'call_id': 'call-1234',
    'room_id': 'room-1234',
    'call_type': 'video',
    'status': 'ongoing',
  };

  ZegoTokenResponse tokenReturn = const ZegoTokenResponse(
    token: 'token-abc-123',
    appId: 99887766,
    userId: 'user-auth-1111',
    expiresAt: 1800000000,
  );

  @override
  Future<Map<String, dynamic>> initiateCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
  }) async {
    initiateCalled = true;
    return initiateReturn;
  }

  @override
  Future<Map<String, dynamic>> acceptCall(String callId) async {
    acceptCalled = true;
    lastCallId = callId;
    return acceptReturn;
  }

  @override
  Future<Map<String, dynamic>> rejectCall(String callId) async {
    rejectCalled = true;
    lastCallId = callId;
    return {'success': true, 'call_id': callId, 'status': 'rejected'};
  }

  @override
  Future<Map<String, dynamic>> cancelCall(String callId) async {
    cancelCalled = true;
    lastCallId = callId;
    return {'success': true, 'call_id': callId, 'status': 'cancelled'};
  }

  @override
  Future<Map<String, dynamic>> leaveCall(String callId) async {
    leaveCalled = true;
    lastCallId = callId;
    return {'success': true, 'call_id': callId, 'status': 'left'};
  }

  @override
  Future<ZegoTokenResponse> getZegoToken({
    String? callId,
    String? roomId,
    int? effectiveTimeInSeconds,
    CallType? callType,
  }) async {
    getTokenCalled = true;
    lastCallId = callId;
    return tokenReturn;
  }

  @override
  Future<Map<String, dynamic>> inviteToCall({required String callId, required List<String> inviteeIds}) async => {};
  @override
  Future<Map<String, dynamic>> rejoinCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) async => {'success': true};
  @override
  Future<CallRecord?> getCallById(String callId) async => null;
  @override
  Future<Map<String, dynamic>> timeoutCall(String callId) async => {};
  @override
  Future<List<CallRecord>> fetchCallHistory({int limit = 50, int offset = 0}) async => [];
  @override
  Stream<List<CallRecord>> watchCallHistory() => const Stream.empty();
  @override
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async => [];
  @override
  Stream<List<CallRecord>> watchCallsForChat(String chatId) => const Stream.empty();
  @override
  void attachConnectionManager(dynamic connectionManager) {}
  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async => const [];
}

class _MockZegoEngineService implements ZegoEngineService {
  bool initialized = false;
  int? initializedAppId;
  bool destroyed = false;

  bool joinRoomCalled = false;
  String? joinedCallId;
  String? joinedRoomId;
  String? joinedUserId;
  String? joinedToken;
  CallType? joinedCallType;

  bool leaveRoomCalled = false;
  bool micMuted = false;
  bool camEnabled = true;
  bool frontCam = true;
  bool speakerOn = false;
  String? renewedToken;

  ZegoCallSession _session = ZegoCallSession.initial();
  final StreamController<ZegoCallSession> _sessionController = StreamController.broadcast();
  final StreamController<int> _tokenExpiryController = StreamController.broadcast();

  @override
  bool get isInitialized => initialized;

  @override
  ZegoCallSession get currentSession => _session;

  @override
  Stream<ZegoCallSession> get sessionStream => _sessionController.stream;

  @override
  Stream<int> get tokenWillExpireStream => _tokenExpiryController.stream;

  void emitSession(ZegoCallSession session) {
    _session = session;
    _sessionController.add(session);
  }

  void emitTokenExpire(int remaining) {
    _tokenExpiryController.add(remaining);
  }

  @override
  Future<void> initializeEngine({required int appId, ZegoCallScenario scenario = ZegoCallScenario.standardCall}) async {
    initialized = true;
    initializedAppId = appId;
  }

  @override
  Future<void> destroyEngine() async {
    initialized = false;
    destroyed = true;
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
    joinRoomCalled = true;
    joinedCallId = callId;
    joinedRoomId = roomId;
    joinedUserId = userId;
    joinedToken = token;
    joinedCallType = callType;
    emitSession(_session.copyWith(
      callId: callId,
      roomId: roomId,
      callType: callType,
      connectionState: ZegoRoomConnectionState.connected,
      participants: {
        userId: ZegoParticipant(userId: userId, userName: userName, isLocal: true),
      },
    ));
  }

  @override
  Future<void> leaveRoom() async {
    leaveRoomCalled = true;
    emitSession(ZegoCallSession.initial());
  }

  @override
  Future<void> muteMicrophone(bool mute) async {
    micMuted = mute;
    emitSession(_session.copyWith(isMicrophoneMuted: mute));
  }

  @override
  Future<void> enableCamera(bool enable) async {
    camEnabled = enable;
    emitSession(_session.copyWith(isCameraEnabled: enable));
  }

  @override
  Future<void> switchCamera() async {
    frontCam = !frontCam;
    emitSession(_session.copyWith(isFrontCamera: frontCam));
  }

  @override
  Future<void> setSpeakerphoneOn(bool enable) async {
    speakerOn = enable;
    emitSession(_session.copyWith(isSpeakerOn: enable));
  }

  @override
  Future<void> renewToken(String token) async {
    renewedToken = token;
  }

  @override
  Future<void> setLocalPreviewView(int? viewId) async {
    emitSession(_session.copyWith(localViewId: viewId));
  }

  @override
  Future<void> setRemoteVideoView({required String streamId, int? viewId}) async {}

  @override
  Future<void> dispose() async {
    await _sessionController.close();
    await _tokenExpiryController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallController Tests', () {
    late _MockCallsRepository mockRepo;
    late _MockZegoEngineService mockEngine;
    late _MockSupabaseClient mockSupabase;
    late ProviderContainer container;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'requestPermissions') {
            final List<dynamic> permissions = methodCall.arguments as List<dynamic>;
            final Map<int, int> result = {};
            for (final p in permissions) {
              result[p as int] = 1; // PermissionStatus.granted
            }
            return result;
          }
          if (methodCall.method == 'checkPermissionStatus') {
            return 1; // PermissionStatus.granted
          }
          return null;
        },
      );

      mockRepo = _MockCallsRepository();
      mockEngine = _MockZegoEngineService();
      mockSupabase = _MockSupabaseClient(); // User null by default

      container = ProviderContainer(
        overrides: [
          callsRepositoryProvider.overrideWithValue(mockRepo),
          zegoEngineServiceProvider.overrideWithValue(mockEngine),
          supabaseClientProvider.overrideWithValue(mockSupabase),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial controller state matches initial session', () {
      final state = container.read(callControllerProvider);
      expect(state.connectionState, ZegoRoomConnectionState.disconnected);
      expect(state.isActive, isFalse);
    });

    test('startOutgoingCall fails when unauthenticated', () async {
      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-1',
        callType: CallType.audio,
        inviteeIds: ['user-2'],
      );

      expect(ok, isFalse);
      expect(container.read(callControllerProvider).errorMessage, contains('unauthenticated'));
    });

    test('acceptIncomingCall fails when unauthenticated', () async {
      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.acceptIncomingCall(
        callId: 'call-1',
        callType: CallType.audio,
      );

      expect(ok, isFalse);
      expect(container.read(callControllerProvider).errorMessage, contains('unauthenticated'));
    });

    test('rejectIncomingCall invokes backend repository', () async {
      final controller = container.read(callControllerProvider.notifier);
      await controller.rejectIncomingCall('call-reject-99');

      expect(mockRepo.rejectCalled, isTrue);
      expect(mockRepo.lastCallId, 'call-reject-99');
    });

    test('Device controls toggle mic, camera, speaker, and camera switch', () async {
      final controller = container.read(callControllerProvider.notifier);

      // Toggle mic
      await controller.toggleMicrophone();
      expect(mockEngine.micMuted, isTrue);

      // Toggle camera
      await controller.toggleCamera();
      expect(mockEngine.camEnabled, isFalse);

      // Switch camera
      await controller.switchCamera();
      expect(mockEngine.frontCam, isFalse);

      // Toggle speaker
      await controller.toggleSpeaker();
      expect(mockEngine.speakerOn, isTrue);
    });

    test('Automatic token renewal triggers when tokenWillExpireStream emits', () async {
      final subscription = container.listen(callControllerProvider, (_, _) {});

      // Set active callId in session
      mockEngine.emitSession(mockEngine.currentSession.copyWith(callId: 'call-active-123'));

      // Emit token expiration
      mockEngine.emitTokenExpire(30);

      // Allow microtasks to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockRepo.getTokenCalled, isTrue);
      expect(mockRepo.lastCallId, 'call-active-123');
      expect(mockEngine.renewedToken, 'token-abc-123');

      subscription.close();
    });

    test('endCall leaves room and notifies backend', () async {
      final subscription = container.listen(callControllerProvider, (_, _) {});
      final controller = container.read(callControllerProvider.notifier);

      mockEngine.emitSession(mockEngine.currentSession.copyWith(
        callId: 'call-terminate-1',
        connectionState: ZegoRoomConnectionState.connected,
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      await controller.endCall();

      expect(mockEngine.leaveRoomCalled, isTrue);
      expect(mockRepo.leaveCalled, isTrue);
      expect(mockRepo.lastCallId, 'call-terminate-1');

      subscription.close();
    });

    const testUser = User(
      id: 'user-auth-1111',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    );

    test('startOutgoingCall fails with descriptive message when backend rejects with call_in_progress', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.initiateReturn = {
        'success': false,
        'error': 'call_in_progress',
        'existing_call_id': 'existing-call-123',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-busy-1',
        callType: CallType.audio,
        inviteeIds: ['user-callee-2'],
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'Another call is already in progress in this chat.',
      );
    });

    test('startOutgoingCall fails with mapped message when backend rejects with other error', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.initiateReturn = {
        'success': false,
        'error': 'server_database_error',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-1',
        callType: CallType.audio,
        inviteeIds: ['user-2'],
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'Call operation failed: server_database_error',
      );
    });

    test('startOutgoingCall fails with missing-identifiers exception when success is true but call_id is null', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.initiateReturn = {
        'success': true,
        'call_id': null,
        'room_id': 'room-1',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-1',
        callType: CallType.audio,
        inviteeIds: ['user-2'],
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'Backend failed to return authoritative call/room identifiers.',
      );
    });

    test('startOutgoingCall succeeds when backend returns success true with valid identifiers', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.initiateReturn = {
        'success': true,
        'call_id': 'call-success-100',
        'room_id': 'room-success-100',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-1',
        callType: CallType.audio,
        inviteeIds: ['user-2'],
      );

      expect(ok, isTrue);
      expect(mockEngine.joinRoomCalled, isTrue);
      expect(mockEngine.joinedCallId, 'call-success-100');
      expect(mockEngine.joinedRoomId, 'room-success-100');
    });

    test('acceptIncomingCall fails with mapped message when backend rejects with call_timed_out', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.acceptReturn = {
        'success': false,
        'error': 'call_timed_out',
        'status': 'missed',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.acceptIncomingCall(
        callId: 'call-stale-99',
        callType: CallType.audio,
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'This call has timed out.',
      );
    });

    test('acceptIncomingCall fails with missing-room-id message when success is true but room_id is empty', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.acceptReturn = {
        'success': true,
        'call_id': 'call-1',
        'room_id': '',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.acceptIncomingCall(
        callId: 'call-1',
        callType: CallType.audio,
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'Backend failed to return authoritative room identifier on acceptance.',
      );
    });

    test('acceptIncomingCall succeeds when backend returns success true with valid room_id', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.acceptReturn = {
        'success': true,
        'call_id': 'call-accepted-1',
        'room_id': 'room-accepted-1',
        'status': 'ongoing',
      };

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.acceptIncomingCall(
        callId: 'call-accepted-1',
        callType: CallType.video,
      );

      expect(ok, isTrue);
      expect(mockEngine.joinRoomCalled, isTrue);
      expect(mockEngine.joinedCallId, 'call-accepted-1');
      expect(mockEngine.joinedRoomId, 'room-accepted-1');
      expect(mockEngine.joinedCallType, CallType.video);
    });

    test('startOutgoingCall fails gracefully on unexpected empty response structure', () async {
      (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
      mockRepo.initiateReturn = {};

      final controller = container.read(callControllerProvider.notifier);
      final ok = await controller.startOutgoingCall(
        chatId: 'chat-1',
        callType: CallType.audio,
        inviteeIds: ['user-2'],
      );

      expect(ok, isFalse);
      expect(
        container.read(callControllerProvider).errorMessage,
        'Call operation failed: initiation_failed',
      );
    });

    group('Stage 2.4 — Immediate Call Push Dispatch Integration', () {
      test('1. Successful call initiation triggers one push dispatch with valid call_id', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': true,
          'call_id': 'call-dispatch-101',
          'room_id': 'room-dispatch-101',
        };

        final controller = container.read(callControllerProvider.notifier);
        final ok = await controller.startOutgoingCall(
          chatId: 'chat-push-1',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-1'],
        );

        expect(ok, isTrue);
        expect(mockSupabase.mockFunctions.invocations.length, 1);
        final invocation = mockSupabase.mockFunctions.invocations.first;
        expect(invocation['functionName'], 'send-push');
        expect(invocation['body'], {'call_id': 'call-dispatch-101'});
      });

      test('2. Failed call initiation (success=false) does not trigger dispatch', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': false,
          'error': 'call_in_progress',
        };

        final controller = container.read(callControllerProvider.notifier);
        final ok = await controller.startOutgoingCall(
          chatId: 'chat-push-1',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-1'],
        );

        expect(ok, isFalse);
        expect(mockSupabase.mockFunctions.invocations, isEmpty);
      });

      test('3. Missing or empty call_id does not trigger dispatch', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': true,
          'call_id': '',
          'room_id': 'room-dispatch-valid',
        };

        final controller = container.read(callControllerProvider.notifier);
        final ok = await controller.startOutgoingCall(
          chatId: 'chat-push-1',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-1'],
        );

        expect(ok, isFalse);
        expect(mockSupabase.mockFunctions.invocations, isEmpty);
      });

      test('4. Push dispatch failure (network exception or HTTP >= 300) does not fail outgoing call', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': true,
          'call_id': 'call-dispatch-fail',
          'room_id': 'room-dispatch-fail',
        };

        // Simulate Edge Function throwing a network exception
        mockSupabase.mockFunctions.handler = (fn, body) async {
          throw Exception('Edge function network failure');
        };

        final controller = container.read(callControllerProvider.notifier);
        final ok = await controller.startOutgoingCall(
          chatId: 'chat-push-1',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-1'],
        );

        // Outgoing call still succeeds because push dispatch error is caught gracefully
        expect(ok, isTrue);
        expect(mockEngine.joinRoomCalled, isTrue);
        expect(mockEngine.joinedCallId, 'call-dispatch-fail');

        // Next test HTTP status >= 300
        mockSupabase.mockFunctions.invocations.clear();
        mockSupabase.mockFunctions.handler = (fn, body) async {
          return const FunctionResponse(status: 500, data: {'error': 'OneSignal down'});
        };

        final ok2 = await controller.startOutgoingCall(
          chatId: 'chat-push-2',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-2'],
        );

        expect(ok2, isTrue);
        expect(mockEngine.joinRoomCalled, isTrue);
      });

      test('5. Push dispatch is asynchronous and does not block ZEGO engine initialization', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': true,
          'call_id': 'call-dispatch-unblocked',
          'room_id': 'room-dispatch-unblocked',
        };

        final pushCompleter = Completer<FunctionResponse>();
        mockSupabase.mockFunctions.handler = (fn, body) => pushCompleter.future;

        final controller = container.read(callControllerProvider.notifier);

        // startOutgoingCall should complete without waiting for pushCompleter
        final callFuture = controller.startOutgoingCall(
          chatId: 'chat-push-async',
          callType: CallType.audio,
          inviteeIds: ['user-invitee-1'],
        );

        final ok = await callFuture;
        expect(ok, isTrue);

        // ZEGO engine was initialized and room joined immediately while push was pending
        expect(mockEngine.initialized, isTrue);
        expect(mockEngine.joinRoomCalled, isTrue);
        expect(mockEngine.joinedCallId, 'call-dispatch-unblocked');
        expect(pushCompleter.isCompleted, isFalse);

        // Complete push afterwards
        pushCompleter.complete(const FunctionResponse(status: 200, data: {'delivered': 1}));
      });

      test('6. Existing calling behavior and state transitions remain unchanged', () async {
        (mockSupabase.auth as _MockGoTrueClient).mockUser = testUser;
        mockRepo.initiateReturn = {
          'success': true,
          'call_id': 'call-verify-existing',
          'room_id': 'room-verify-existing',
        };

        final controller = container.read(callControllerProvider.notifier);
        final ok = await controller.startOutgoingCall(
          chatId: 'chat-verify',
          callType: CallType.video,
          inviteeIds: ['user-invitee-1'],
          localUserName: 'Custom Caller Name',
        );

        expect(ok, isTrue);
        expect(mockEngine.joinRoomCalled, isTrue);
        expect(mockEngine.joinedCallType, CallType.video);
        final session = container.read(callControllerProvider);
        expect(session.callId, 'call-verify-existing');
        expect(session.roomId, 'room-verify-existing');
        expect(session.callType, CallType.video);
      });
    });
  });
}
