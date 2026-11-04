// test/notifications/notification_routing_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/notification_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/domain/models/notification_payload.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_navigation_coordinator.dart';

class _FakeCallsRepository implements CallsRepository {
  final List<String> rejectedCalls = [];

  @override
  Future<Map<String, dynamic>> rejectCall(String callId) async {
    rejectedCalls.add(callId);
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> acceptCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> cancelCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> initiateCall({required String chatId, required CallType callType, required List<String> inviteeIds}) async => {'success': true};
  @override
  Future<Map<String, dynamic>> inviteToCall({required String callId, required List<String> inviteeIds}) async => {'success': true};
  @override
  Future<Map<String, dynamic>> leaveCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> rejoinCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) async => {'success': true};
  @override
  Future<CallRecord?> getCallById(String callId) async => null;
  @override
  Future<Map<String, dynamic>> timeoutCall(String callId) async => {'success': true};
  @override
  Future<ZegoTokenResponse> getZegoToken({String? callId, String? roomId, int? effectiveTimeInSeconds, CallType? callType}) async =>
      const ZegoTokenResponse(token: 't', appId: 1, userId: 'u', expiresAt: 1);
  @override
  void attachConnectionManager(dynamic connectionManager) {}
  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async => const [];
  @override
  Future<List<CallRecord>> fetchCallHistory({int limit = 50, int offset = 0}) async => const [];
  @override
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async => const [];
  @override
  Stream<List<CallRecord>> watchCallHistory() => const Stream.empty();
  @override
  Stream<List<CallRecord>> watchCallsForChat(String chatId) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationPayload Parser Tests', () {
    test('Parses message notification with camelCase keys', () {
      final data = {
        'chatId': 'chat-123',
        'messageId': 'msg-456',
        'type': 'chat',
        'senderName': 'Alice',
      };
      final payload = NotificationPayload.fromMap(data);
      expect(payload.type, NotificationType.chat);
      expect(payload.chatId, 'chat-123');
      expect(payload.messageId, 'msg-456');
      expect(payload.callerName, 'Alice');
      expect(payload.isChat, isTrue);
      expect(payload.isCall, isFalse);
    });

    test('Parses message notification with snake_case keys', () {
      final data = {
        'chat_id': 'chat-789',
        'message_id': 'msg-012',
        'sender_phone': '+15551234567',
      };
      final payload = NotificationPayload.fromMap(data);
      expect(payload.type, NotificationType.chat);
      expect(payload.chatId, 'chat-789');
      expect(payload.messageId, 'msg-012');
      expect(payload.senderPhone, '+15551234567');
    });

    test('Parses call notification (body tap -> openIncomingUi)', () {
      final data = {
        'callId': 'call-abc',
        'callerId': 'user-1',
        'callerName': 'Bob',
        'callType': 'video',
        'type': 'call',
      };
      final payload = NotificationPayload.fromMap(data);
      expect(payload.type, NotificationType.call);
      expect(payload.callId, 'call-abc');
      expect(payload.callerId, 'user-1');
      expect(payload.callerName, 'Bob');
      expect(payload.callType, 'video');
      expect(payload.callActionIntent, CallActionIntent.openIncomingUi);
      expect(payload.isCall, isTrue);
    });

    test('Parses call notification with actionId accept', () {
      final data = {
        'call_id': 'call-def',
        'call_type': 'audio',
      };
      final payload = NotificationPayload.fromMap(data, actionId: 'accept');
      expect(payload.type, NotificationType.call);
      expect(payload.callId, 'call-def');
      expect(payload.callType, 'audio');
      expect(payload.callActionIntent, CallActionIntent.accept);
    });

    test('Parses call notification with actionId decline/reject', () {
      final data = {
        'callId': 'call-ghi',
      };
      final payload1 = NotificationPayload.fromMap(data, actionId: 'decline');
      expect(payload1.callActionIntent, CallActionIntent.decline);

      final payload2 = NotificationPayload.fromMap(data, actionId: 'REJECT');
      expect(payload2.callActionIntent, CallActionIntent.decline);
    });

    test('Parses call_cancelled payload', () {
      final data = {
        'callId': 'call-jkl',
        'type': 'call_cancelled',
      };
      final payload = NotificationPayload.fromMap(data);
      expect(payload.type, NotificationType.callCancelled);
      expect(payload.callId, 'call-jkl');
      expect(payload.isCallCancelled, isTrue);
    });

    test('Safely handles null, empty, or whitespace data', () {
      final p1 = NotificationPayload.fromMap(null);
      expect(p1.type, NotificationType.unknown);

      final p2 = NotificationPayload.fromMap({});
      expect(p2.type, NotificationType.unknown);

      final p3 = NotificationPayload.fromStringPayload('');
      expect(p3.type, NotificationType.unknown);
    });

    test('Parses string JSON payload and raw string chatId fallback', () {
      final jsonPayload =
          NotificationPayload.fromStringPayload('{"chatId": "chat-999"}');
      expect(jsonPayload.type, NotificationType.chat);
      expect(jsonPayload.chatId, 'chat-999');

      final rawStringPayload =
          NotificationPayload.fromStringPayload('chat-raw-string');
      expect(rawStringPayload.type, NotificationType.chat);
      expect(rawStringPayload.chatId, 'chat-raw-string');
    });

    test('Parses nested JSON string in "data" or "custom" fields', () {
      final nestedData = {
        'data': '{"chatId": "chat-nested-123", "messageId": "msg-nested-456", "type": "chat"}'
      };
      final p1 = NotificationPayload.fromMap(nestedData);
      expect(p1.type, NotificationType.chat);
      expect(p1.chatId, 'chat-nested-123');
      expect(p1.messageId, 'msg-nested-456');

      final oneSignalCustom = {
        'custom': {
          'a': {
            'callId': 'call-custom-789',
            'callerName': 'Alice',
            'type': 'call',
          }
        }
      };
      final p2 = NotificationPayload.fromMap(oneSignalCustom);
      expect(p2.type, NotificationType.call);
      expect(p2.callId, 'call-custom-789');
      expect(p2.callerName, 'Alice');
    });
  });

  group('NotificationNavigationCoordinator Tests', () {
    late RouterNotifier routerNotifier;
    late _FakeCallsRepository fakeCallsRepo;
    late List<String> pushedRoutes;
    late Map<String, dynamic> lastPushedExtra;
    late GoRouter testRouter;

    setUp(() {
      routerNotifier = RouterNotifier();
      fakeCallsRepo = _FakeCallsRepository();
      pushedRoutes = [];
      lastPushedExtra = {};

      testRouter = GoRouter(
        initialLocation: '/chats',
        routes: [
          GoRoute(path: '/chats', builder: (_, _) => const Scaffold(body: Text('ChatsScreen'))),
          GoRoute(
            path: '/chats/chat/:chatId',
            builder: (context, state) {
              pushedRoutes.add(state.uri.toString());
              if (state.extra is Map<String, dynamic>) {
                lastPushedExtra = state.extra as Map<String, dynamic>;
              }
              return Scaffold(body: Text('ChatScreen:${state.pathParameters['chatId']}'));
            },
          ),
          GoRoute(
            path: '/call/:callId',
            builder: (context, state) {
              pushedRoutes.add(state.uri.toString());
              return Scaffold(body: Text('CallScreen:${state.pathParameters['callId']}'));
            },
          ),
        ],
      );

      NotificationController.onChatClose('chat-already-open');
    });

    testWidgets('Cold start / unauthed: Buffers payload until router is authed & bootstrapped', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      // Router starts not authed, not bootstrapped
      expect(routerNotifier.isAuthed, isFalse);
      expect(routerNotifier.bootstrapped, isFalse);

      final payload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'cold-start-chat-1',
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      // Must be buffered, not yet pushed to GoRouter
      expect(coordinator.pendingPayload, isNotNull);
      expect(coordinator.pendingPayload?.chatId, 'cold-start-chat-1');
      expect(routerNotifier.pendingNotification, isNotNull);
      expect(pushedRoutes, isEmpty);

      // Simulate authentication and bootstrap completion
      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);
      await tester.pumpAndSettle();

      // Buffered payload must now be dispatched and cleared
      expect(coordinator.pendingPayload, isNull);
      expect(pushedRoutes, contains('/chats/chat/cold-start-chat-1'));
    });

    testWidgets('Chat navigation with messageId passes targetMessageId in extra', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      final payload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'chat-target-msg',
        messageId: 'target-uuid-1234',
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains('/chats/chat/chat-target-msg'));
      expect(lastPushedExtra['targetMessageId'], 'target-uuid-1234');
    });

    testWidgets('Chat navigation suppresses duplicate push when chat is already foreground open', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      // Mark chat as currently open
      NotificationController.onChatOpen('chat-already-open');

      final payload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'chat-already-open',
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      // Duplicate push must be skipped
      expect(pushedRoutes, isEmpty);
    });

    testWidgets('Call notification body tap navigates with incoming=true (Never auto-joins ZEGO)', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      final payload = const NotificationPayload(
        type: NotificationType.call,
        callId: 'call-999',
        callerId: 'user-bob',
        callerName: 'Bob Smith',
        callType: 'audio',
        callActionIntent: CallActionIntent.openIncomingUi,
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      expect(pushedRoutes.length, 1);
      final pushedUri = pushedRoutes.first;
      expect(pushedUri, contains('/call/call-999'));
      expect(pushedUri, contains('incoming=true'));
      expect(pushedUri, contains('userID=user-bob'));
      expect(pushedUri, contains('userName=Bob%20Smith'));
      expect(pushedUri, contains('callType=audio'));
    });

    testWidgets('Call notification explicit decline action button calls rejectCall without navigating', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      final payload = const NotificationPayload(
        type: NotificationType.call,
        callId: 'call-declined-1',
        callActionIntent: CallActionIntent.decline,
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      expect(pushedRoutes, isEmpty);
      expect(fakeCallsRepo.rejectedCalls, contains('call-declined-1'));
    });

    testWidgets('Rapid duplicate notification tap within 1000ms is debounced at coordinator level', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      final payload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'chat-debounce-target',
      );

      // First tap executes navigation
      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();
      expect(pushedRoutes, contains('/chats/chat/chat-debounce-target'));
      final countAfterFirst = pushedRoutes.length;

      // Immediate second tap for the same payload signature is debounced
      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();
      expect(pushedRoutes.length, equals(countAfterFirst),
          reason: 'Duplicate tap within 1000ms must be debounced without triggering new navigation');

      // Different payload goes through immediately
      final differentPayload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'chat-different-target',
      );
      await coordinator.handleNotificationPayload(differentPayload);
      await tester.pumpAndSettle();
      expect(pushedRoutes, contains('/chats/chat/chat-different-target'));
    });

    testWidgets('Route state deduplication: suppresses duplicate call screen push if callId route is already active', (tester) async {
      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
      await tester.pumpAndSettle();

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: testRouter,
        callsRepository: fakeCallsRepo,
      );

      final callPayload = const NotificationPayload(
        type: NotificationType.call,
        callId: 'call-active-state',
      );

      // First tap navigates to call screen
      await coordinator.handleNotificationPayload(callPayload);
      await tester.pumpAndSettle();
      expect(pushedRoutes.any((r) => r.contains('/call/call-active-state')), isTrue);
      final countBeforeSecond = pushedRoutes.length;

      // Second tap for the same call screen while route is already active does NOT push duplicate
      await coordinator.handleNotificationPayload(callPayload);
      await tester.pumpAndSettle();
      expect(pushedRoutes.length, equals(countBeforeSecond),
          reason: 'Duplicate call push must be suppressed when call screen is already active route');
    });

    testWidgets('Cold-start at /splash delegates to GoRouter redirect and preserves pendingNotification', (tester) async {
      final splashRouter = GoRouter(
        initialLocation: '/splash',
        routes: [
          GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Text('SplashScreen'))),
          GoRoute(path: '/chats', builder: (_, _) => const Scaffold(body: Text('ChatsScreen'))),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: splashRouter));
      await tester.pumpAndSettle();

      final coordinator = NotificationNavigationCoordinator(
        routerNotifier: routerNotifier,
        goRouter: splashRouter,
        callsRepository: fakeCallsRepo,
      );

      final payload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'splash-cold-start-chat',
      );

      await coordinator.handleNotificationPayload(payload);
      await tester.pumpAndSettle();

      expect(routerNotifier.pendingNotification, isNotNull);
      expect(routerNotifier.pendingNotificationChatId, 'splash-cold-start-chat');

      // Router state becomes authed and bootstrapped while on /splash
      routerNotifier.setAuthed(true);
      routerNotifier.setBootstrapped(true);
      await tester.pumpAndSettle();

      // Coordinator must NOT have wiped routerNotifier.pendingNotification
      // because current route was /splash!
      expect(routerNotifier.pendingNotification, isNotNull);
      expect(routerNotifier.pendingNotificationChatId, 'splash-cold-start-chat');
    });
  });

  group('NotificationController Candidate Draining Tests', () {
    test('Drains valid payload over unknown/null payloads', () {
      NotificationController.resetForTesting();
      OneSignalService.pendingNotificationPayload =
          const NotificationPayload(type: NotificationType.unknown);
      FcmService.pendingNotificationPayload = const NotificationPayload(
        type: NotificationType.chat,
        chatId: 'fcm-valid-chat',
      );
      NotificationService.pendingNotificationPayload = null;

      final fakeCoordinator = NotificationNavigationCoordinator(
        routerNotifier: RouterNotifier(),
        goRouter: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]),
        callsRepository: _FakeCallsRepository(),
      );

      NotificationController.configureCoordinator(fakeCoordinator);
      expect(fakeCoordinator.pendingPayload?.chatId, equals('fcm-valid-chat'));
    });
  });
}
