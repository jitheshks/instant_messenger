// test/calls/calling_ui_test.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_call_models.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/services/zego_engine_service.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/calls/presentation/screens/call_screen.dart';
import 'package:instant_messenger/features/calls/presentation/widgets/call_avatar.dart';
import 'package:instant_messenger/features/calls/presentation/widgets/call_controls_bar.dart';
import 'package:instant_messenger/features/calls/presentation/widgets/call_duration_timer.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockGoTrueClient implements GoTrueClient {
  final User? _user;
  _MockGoTrueClient(this._user);

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSupabaseClient implements SupabaseClient {
  final _MockGoTrueClient _auth;
  _MockSupabaseClient({User? user}) : _auth = _MockGoTrueClient(user);

  @override
  GoTrueClient get auth => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockCallsRepository implements CallsRepository {
  bool rejectCalled = false;
  bool acceptCalled = false;
  String? lastCallId;

  @override
  Future<Map<String, dynamic>> rejectCall(String callId) async {
    rejectCalled = true;
    lastCallId = callId;
    return {'status': 'rejected', 'success': true};
  }

  @override
  Future<Map<String, dynamic>> acceptCall(String callId) async {
    acceptCalled = true;
    lastCallId = callId;
    return {
      'call_id': callId,
      'room_id': 'room-$callId',
      'call_type': 'audio',
      'status': 'ongoing',
      'success': true,
    };
  }

  @override
  Future<ZegoTokenResponse> getZegoToken({
    String? callId,
    String? roomId,
    int? effectiveTimeInSeconds,
    CallType? callType,
  }) async {
    return const ZegoTokenResponse(
      token: 'mock-token',
      appId: 123456,
      userId: 'user-1',
      expiresAt: 1999999999,
    );
  }

  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) async => {'success': true};

  CallRecord? getCallByIdReturn;

  @override
  Future<CallRecord?> getCallById(String callId) async => getCallByIdReturn;

  @override
  Future<Map<String, dynamic>> leaveCall(String callId) async => {'success': true};

  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockZegoEngineService implements ZegoEngineService {
  ZegoCallSession session = ZegoCallSession.initial();
  final _sessionController = StreamController<ZegoCallSession>.broadcast();
  final _tokenController = StreamController<int>.broadcast();

  @override
  ZegoCallSession get currentSession => session;

  @override
  Stream<ZegoCallSession> get sessionStream => _sessionController.stream;

  @override
  Stream<int> get tokenWillExpireStream => _tokenController.stream;

  @override
  Future<void> initializeEngine({required int appId, dynamic scenario}) async {}

  @override
  Future<void> joinRoom({
    required String callId,
    required String roomId,
    required String userId,
    required String userName,
    required String token,
    required CallType callType,
  }) async {
    session = session.copyWith(
      callId: callId,
      roomId: roomId,
      connectionState: ZegoRoomConnectionState.connected,
      callType: callType,
    );
    _sessionController.add(session);
  }

  @override
  Future<void> leaveRoom() async {
    session = ZegoCallSession.initial();
    _sessionController.add(session);
  }

  @override
  Future<void> muteMicrophone(bool mute) async {
    session = session.copyWith(isMicrophoneMuted: mute);
    _sessionController.add(session);
  }

  @override
  Future<void> enableCamera(bool enable) async {
    session = session.copyWith(isCameraEnabled: enable);
    _sessionController.add(session);
  }

  @override
  Future<void> switchCamera() async {
    session = session.copyWith(isFrontCamera: !session.isFrontCamera);
    _sessionController.add(session);
  }

  @override
  Future<void> setSpeakerphoneOn(bool enable) async {
    session = session.copyWith(isSpeakerOn: enable);
    _sessionController.add(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // 1. CallDurationTimer Widget Tests
  // ---------------------------------------------------------------------------
  group('CallDurationTimer Widget Tests', () {
    testWidgets('formats seconds into MM:SS correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallDurationTimer(
              isRunning: true,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('increments elapsed duration over time when running', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallDurationTimer(
              isRunning: true,
              initialElapsedSeconds: 10,
            ),
          ),
        ),
      );

      expect(find.text('00:10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:12'), findsOneWidget);
    });

    testWidgets('formats durations over an hour into HH:MM:SS', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallDurationTimer(
              isRunning: false,
              initialElapsedSeconds: 3725,
            ),
          ),
        ),
      );

      expect(find.text('01:02:05'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. CallControlsBar Widget Tests
  // ---------------------------------------------------------------------------
  group('CallControlsBar Widget Tests', () {
    testWidgets('renders all controls and triggers callbacks correctly', (tester) async {
      bool micToggled = false;
      bool cameraToggled = false;
      bool speakerToggled = false;
      bool cameraSwitched = false;
      bool callEnded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControlsBar(
              isVideoCall: true,
              isMicrophoneMuted: false,
              isCameraEnabled: true,
              isSpeakerOn: true,
              isFrontCamera: true,
              onToggleMicrophone: () => micToggled = true,
              onToggleCamera: () => cameraToggled = true,
              onToggleSpeaker: () => speakerToggled = true,
              onSwitchCamera: () => cameraSwitched = true,
              onEndCall: () => callEnded = true,
            ),
          ),
        ),
      );

      // Verify buttons exist
      expect(find.byTooltip('Mute Microphone'), findsOneWidget);
      expect(find.byTooltip('Turn Off Camera'), findsOneWidget);
      expect(find.byTooltip('Speaker On'), findsOneWidget);
      expect(find.byTooltip('Switch to Rear Camera'), findsOneWidget);
      expect(find.byTooltip('End Call'), findsOneWidget);

      // Tap Mute
      await tester.tap(find.byTooltip('Mute Microphone'));
      await tester.pump();
      expect(micToggled, isTrue);

      // Tap Camera
      await tester.tap(find.byTooltip('Turn Off Camera'));
      await tester.pump();
      expect(cameraToggled, isTrue);

      // Tap Speaker
      await tester.tap(find.byTooltip('Speaker On'));
      await tester.pump();
      expect(speakerToggled, isTrue);

      // Tap Switch Camera
      await tester.tap(find.byTooltip('Switch to Rear Camera'));
      await tester.pump();
      expect(cameraSwitched, isTrue);

      // Tap End Call
      await tester.tap(find.byTooltip('End Call'));
      await tester.pump();
      expect(callEnded, isTrue);
    });

    testWidgets('omits flip camera button for audio call', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControlsBar(
              isVideoCall: false,
              isMicrophoneMuted: false,
              isCameraEnabled: false,
              isSpeakerOn: false,
              isFrontCamera: true,
              onToggleMicrophone: () {},
              onToggleCamera: () {},
              onToggleSpeaker: () {},
              onSwitchCamera: () {},
              onEndCall: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('Switch to Rear Camera'), findsNothing);
      expect(find.byTooltip('End Call'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. CallAvatar Widget Tests
  // ---------------------------------------------------------------------------
  group('CallAvatar Widget Tests', () {
    testWidgets('displays caller name, initials fallback, and status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CallAvatar(
              name: 'Alice Wonderland',
              statusText: 'Ringing...',
              radius: 60,
            ),
          ),
        ),
      );

      expect(find.text('AW'), findsOneWidget);
      expect(find.text('Alice Wonderland'), findsOneWidget);
      expect(find.text('Ringing...'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. CallScreen Widget Tests
  // ---------------------------------------------------------------------------
  group('CallScreen Widget Tests', () {
    late _MockCallsRepository mockRepo;
    late _MockZegoEngineService mockEngine;
    late ProviderContainer container;

    setUp(() {
      mockRepo = _MockCallsRepository();
      mockEngine = _MockZegoEngineService();

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

      container = ProviderContainer(
        overrides: [
          callsRepositoryProvider.overrideWithValue(mockRepo),
          zegoEngineServiceProvider.overrideWithValue(mockEngine),
          supabaseClientProvider.overrideWithValue(
            _MockSupabaseClient(
              user: const User(
                id: 'user-1',
                appMetadata: {},
                userMetadata: {},
                aud: 'authenticated',
                createdAt: '2026-01-01',
              ),
            ),
          ),
        ],
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
      container.dispose();
    });

    testWidgets('renders incoming ringing view with Accept and Decline buttons', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CallScreen(
              callID: 'call-incoming-1',
              userID: 'caller-user-id',
              userName: 'Bob Vance',
              callType: CallType.audio,
              isIncoming: true,
            ),
          ),
        ),
      );

      expect(find.text('Bob Vance'), findsOneWidget);
      expect(find.text('Incoming Voice Call...'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('renders stale call view when server reports call has already ended', (tester) async {
      mockRepo.getCallByIdReturn = CallRecord(
        id: 'call-stale-1',
        chatId: 'chat-1',
        callerId: 'user-caller',
        callType: CallType.audio,
        isGroup: false,
        status: CallStatus.ended,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CallScreen(
              callID: 'call-stale-1',
              userID: 'caller-user-id',
              userName: 'Bob Vance',
              callType: CallType.audio,
              isIncoming: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('This call has already ended.'), findsOneWidget);
      expect(find.byKey(const Key('btn_dismiss_stale_call')), findsOneWidget);
      expect(find.byKey(const Key('btn_accept_call')), findsNothing);
      expect(find.byKey(const Key('btn_decline_call')), findsNothing);
    });

    testWidgets('clicking Decline on incoming ringing view rejects call', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CallScreen(
              callID: 'call-incoming-reject',
              userID: 'caller-user-id',
              userName: 'Bob Vance',
              callType: CallType.audio,
              isIncoming: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn_decline_call')));
      await tester.pumpAndSettle();

      expect(mockRepo.rejectCalled, isTrue);
      expect(mockRepo.lastCallId, equals('call-incoming-reject'));
    });

    testWidgets('clicking Accept on incoming ringing view accepts call and transitions to active view', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CallScreen(
              callID: 'call-incoming-accept',
              userID: 'caller-user-id',
              userName: 'Bob Vance',
              callType: CallType.audio,
              isIncoming: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn_accept_call')));
      await tester.pumpAndSettle();

      expect(mockRepo.acceptCalled, isTrue);
      expect(mockRepo.lastCallId, equals('call-incoming-accept'));
      // Ringing screen buttons are replaced by active call view
      expect(find.text('Decline'), findsNothing);
      expect(find.byTooltip('End Call'), findsOneWidget);

      // Cleanly terminate active call to stop background heartbeat timers
      await tester.tap(find.byTooltip('End Call'));
      await tester.pumpAndSettle();
    });

    testWidgets('renders active outgoing/connected view when isIncoming is false', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CallScreen(
              callID: 'call-outgoing-1',
              userID: 'peer-user-id',
              userName: 'Charlie',
              callType: CallType.audio,
              isIncoming: false,
            ),
          ),
        ),
      );

      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Ringing...'), findsWidgets);
      expect(find.byTooltip('End Call'), findsOneWidget);
      expect(find.byTooltip('Mute Microphone'), findsOneWidget);
      expect(find.byTooltip('Speaker Off'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. OneSignal Notification Integration Tests
  // ---------------------------------------------------------------------------
  group('OneSignal Notification Action & Routing Tests', () {
    test('OneSignalService buffers and drains pending call actions', () {
      const action = CallNotificationAction(
        callId: 'call-buffered-99',
        callerId: 'caller-user-99',
        callerName: 'Diana Prince',
        callType: 'video',
        isAccepted: true,
      );

      OneSignalService.pendingCallAction = action;

      final consumed = OneSignalService.consumePendingCallAction();
      expect(consumed, isNotNull);
      expect(consumed!.callId, equals('call-buffered-99'));
      expect(consumed.callerName, equals('Diana Prince'));
      expect(consumed.callType, equals('video'));
      expect(consumed.isAccepted, isTrue);

      // Verify second consumption is null
      expect(OneSignalService.consumePendingCallAction(), isNull);
    });

    test('NotificationController.configure routes buffered call notification', () {
      const action = CallNotificationAction(
        callId: 'call-cfg-1',
        callerId: 'user-cfg-1',
        callerName: 'Evan Stone',
        callType: 'audio',
        isAccepted: false,
      );

      OneSignalService.pendingCallAction = action;

      CallNotificationAction? routedAction;
      NotificationController.configure(
        (_) {},
        onCallAction: (act) {
          routedAction = act;
        },
      );

      expect(routedAction, isNotNull);
      expect(routedAction!.callId, equals('call-cfg-1'));
      expect(routedAction!.callerName, equals('Evan Stone'));
      expect(routedAction!.isAccepted, isFalse);
    });
  });
}
