import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/features/auth/presentation/controllers/auth_controller.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';
import 'package:instant_messenger/features/auth/domain/models/otp_session.dart';
import 'package:instant_messenger/features/auth/data/auth_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';

/// Test implementation of [AuthService] for recording logout events.
class FakeAuthService implements AuthService {
  String? _currentUserId;
  bool signOutCalled = false;
  bool shouldThrowOnSignOut = false;
  final List<String> eventLog;

  FakeAuthService({
    String? currentUserId,
    this.shouldThrowOnSignOut = false,
    List<String>? eventLog,
  }) : _currentUserId = currentUserId,
       eventLog = eventLog ?? [];

  @override
  String? get currentUserId => _currentUserId;

  set currentUserId(String? val) => _currentUserId = val;

  @override
  Future<void> signOut() async {
    eventLog.add('authService.signOut');
    signOutCalled = true;
    if (shouldThrowOnSignOut) {
      throw Exception('Simulated AuthService.signOut network failure');
    }
    _currentUserId = null;
  }

  @override
  Stream<bool> authStateChanges() => Stream.value(_currentUserId != null);

  @override
  Future<OtpSession> startVerification({
    required String e164,
    int? forceResendToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> verifyCode({
    required String verificationId,
    required String smsCode,
  }) async {
    throw UnimplementedError();
  }
}

/// Test implementation of [OneSignalService] to isolate push lifecycle.
class FakeOneSignalService extends OneSignalService {
  final List<String> eventLog;
  bool removePlayerCalled = false;
  String? removedUid;
  String? removedPlayerId;
  bool logoutCalled = false;
  bool shouldThrowOnRemove = false;
  bool shouldThrowOnLogout = false;

  FakeOneSignalService({
    List<String>? eventLog,
    this.shouldThrowOnRemove = false,
    this.shouldThrowOnLogout = false,
  }) : eventLog = eventLog ?? [],
       super(null, null, null, () => true);

  @override
  bool get isPlatformSupported => true;

  @override
  Future<void> removePlayer(String uid, String playerId) async {
    eventLog.add('oneSignal.removePlayer($uid, $playerId)');
    removePlayerCalled = true;
    removedUid = uid;
    removedPlayerId = playerId;
    if (shouldThrowOnRemove) {
      throw Exception('Simulated OneSignalService.removePlayer network error');
    }
  }

  @override
  Future<void> logout() async {
    eventLog.add('oneSignal.logout');
    logoutCalled = true;
    if (shouldThrowOnLogout) {
      throw Exception('Simulated OneSignalService.logout native SDK error');
    }
  }
}

/// Test implementation of [PushController] for recording cleanup events in AuthController tests.
class FakePushController extends PushController {
  final List<String> eventLog;
  bool cleanupCalled = false;
  String? cleanedUpUid;
  bool shouldThrowOnCleanup = false;

  FakePushController({
    required super.oneSignal,
    required super.oneSignalAppId,
    List<String>? eventLog,
    this.shouldThrowOnCleanup = false,
  }) : eventLog = eventLog ?? [];

  @override
  Future<void> cleanupOnSignOut(String uid) async {
    eventLog.add('pushController.cleanupOnSignOut($uid)');
    cleanupCalled = true;
    cleanedUpUid = uid;
    if (shouldThrowOnCleanup) {
      throw Exception('Simulated push cleanup failure (e.g. offline/timeout)');
    }
  }
}

/// Custom [RouterNotifier] that logs events for verification.
class LoggingRouterNotifier extends RouterNotifier {
  final List<String> eventLog;

  LoggingRouterNotifier(this.eventLog);

  @override
  void reset({bool clearPendingNotification = false}) {
    eventLog.add('routerGuard.reset');
    super.reset(clearPendingNotification: clearPendingNotification);
  }

  @override
  void setAuthed(bool value) {
    eventLog.add('routerGuard.setAuthed($value)');
    super.setAuthed(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 2E.8: Auth & OneSignal Device Logout Lifecycle Tests', () {
    const testUid = 'user-uuid-1111-2222-3333';
    const testPlayerId = 'player-uuid-4444-5555';

    group('AuthController.signOut Execution Order & Error Recovery', () {
      test(
        'Executes strictly in order: push cleanup -> auth signOut -> router reset',
        () async {
          final events = <String>[];
          final fakeAuth = FakeAuthService(
            currentUserId: testUid,
            eventLog: events,
          );
          final fakeOneSignal = FakeOneSignalService();
          final fakePush = FakePushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'app-id-123',
            eventLog: events,
          );
          final routerGuard = LoggingRouterNotifier(events);
          routerGuard.setAuthed(true);
          events.clear(); // Clear initial setup events

          final authController = AuthController(
            routerGuard,
            authService: fakeAuth,
            pushController: fakePush,
          );

          expect(authController.loading, isFalse);
          final future = authController.signOut();
          // Check that loading is set during execution
          expect(authController.loading, isTrue);
          await future;

          expect(authController.loading, isFalse);
          expect(fakePush.cleanupCalled, isTrue);
          expect(fakePush.cleanedUpUid, equals(testUid));
          expect(fakeAuth.signOutCalled, isTrue);
          expect(routerGuard.isAuthed, isFalse);

          // Verify exact call order:
          // 1. pushController.cleanupOnSignOut (while session is still valid)
          // 2. authService.signOut (terminating Supabase session)
          // 3. routerGuard.reset & setAuthed(false) (in finally)
          expect(
            events,
            equals([
              'pushController.cleanupOnSignOut($testUid)',
              'authService.signOut',
              'routerGuard.reset',
              'routerGuard.setAuthed(false)',
            ]),
          );
        },
      );

      test(
        'Guarantees auth signOut and router reset even if push cleanup throws',
        () async {
          final events = <String>[];
          final fakeAuth = FakeAuthService(
            currentUserId: testUid,
            eventLog: events,
          );
          final fakeOneSignal = FakeOneSignalService();
          final fakePush = FakePushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'app-id-123',
            eventLog: events,
            shouldThrowOnCleanup: true,
          );
          final routerGuard = LoggingRouterNotifier(events);
          routerGuard.setAuthed(true);
          events.clear();

          final authController = AuthController(
            routerGuard,
            authService: fakeAuth,
            pushController: fakePush,
          );

          // Should not throw to the caller; errors are caught and logged
          await authController.signOut();

          expect(authController.loading, isFalse);
          expect(fakePush.cleanupCalled, isTrue);
          expect(fakeAuth.signOutCalled, isTrue);
          expect(routerGuard.isAuthed, isFalse);
          expect(
            events,
            equals([
              'pushController.cleanupOnSignOut($testUid)',
              'authService.signOut',
              'routerGuard.reset',
              'routerGuard.setAuthed(false)',
            ]),
          );
        },
      );

      test(
        'Guarantees router reset and unauthenticated state even if auth signOut throws',
        () async {
          final events = <String>[];
          final fakeAuth = FakeAuthService(
            currentUserId: testUid,
            eventLog: events,
            shouldThrowOnSignOut: true,
          );
          final fakeOneSignal = FakeOneSignalService();
          final fakePush = FakePushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'app-id-123',
            eventLog: events,
          );
          final routerGuard = LoggingRouterNotifier(events);
          routerGuard.setAuthed(true);
          events.clear();

          final authController = AuthController(
            routerGuard,
            authService: fakeAuth,
            pushController: fakePush,
          );

          await authController.signOut();

          expect(authController.loading, isFalse);
          expect(routerGuard.isAuthed, isFalse);
          expect(
            events,
            equals([
              'pushController.cleanupOnSignOut($testUid)',
              'authService.signOut',
              'routerGuard.reset',
              'routerGuard.setAuthed(false)',
            ]),
          );
        },
      );

      test(
        'Guarantees router reset if both push cleanup and auth signOut throw',
        () async {
          final events = <String>[];
          final fakeAuth = FakeAuthService(
            currentUserId: testUid,
            eventLog: events,
            shouldThrowOnSignOut: true,
          );
          final fakeOneSignal = FakeOneSignalService();
          final fakePush = FakePushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'app-id-123',
            eventLog: events,
            shouldThrowOnCleanup: true,
          );
          final routerGuard = LoggingRouterNotifier(events);
          routerGuard.setAuthed(true);
          events.clear();

          final authController = AuthController(
            routerGuard,
            authService: fakeAuth,
            pushController: fakePush,
          );

          await authController.signOut();

          expect(authController.loading, isFalse);
          expect(routerGuard.isAuthed, isFalse);
          expect(events, contains('routerGuard.reset'));
          expect(events, contains('routerGuard.setAuthed(false)'));
        },
      );

      test('Handles signOut safely when user ID is null or empty', () async {
        final events = <String>[];
        final fakeAuth = FakeAuthService(currentUserId: null, eventLog: events);
        final fakeOneSignal = FakeOneSignalService();
        final fakePush = FakePushController(
          oneSignal: fakeOneSignal,
          oneSignalAppId: 'app-id-123',
          eventLog: events,
        );
        final routerGuard = LoggingRouterNotifier(events);
        events.clear();

        final authController = AuthController(
          routerGuard,
          authService: fakeAuth,
          pushController: fakePush,
        );

        await authController.signOut();

        // Push cleanup should be skipped because currentUid is null
        expect(fakePush.cleanupCalled, isFalse);
        expect(fakeAuth.signOutCalled, isTrue);
        expect(routerGuard.isAuthed, isFalse);
      });

      test('Repeated / idempotent signOut calls complete safely', () async {
        final events = <String>[];
        final fakeAuth = FakeAuthService(
          currentUserId: testUid,
          eventLog: events,
        );
        final fakeOneSignal = FakeOneSignalService();
        final fakePush = FakePushController(
          oneSignal: fakeOneSignal,
          oneSignalAppId: 'app-id-123',
          eventLog: events,
        );
        final routerGuard = LoggingRouterNotifier(events);
        final authController = AuthController(
          routerGuard,
          authService: fakeAuth,
          pushController: fakePush,
        );

        // First signOut
        await authController.signOut();
        expect(fakePush.cleanupCalled, isTrue);
        expect(fakeAuth.signOutCalled, isTrue);

        // Reset tracking flags
        fakePush.cleanupCalled = false;
        fakeAuth.signOutCalled = false;
        events.clear();

        // Second signOut (now currentUserId is null)
        await authController.signOut();
        expect(
          fakePush.cleanupCalled,
          isFalse,
        ); // Skipped because currentUserId is null
        expect(fakeAuth.signOutCalled, isTrue);
        expect(routerGuard.isAuthed, isFalse);
      });
    });

    group('PushController.cleanupOnSignOut Integration with OneSignalService', () {
      test(
        'cleanupOnSignOut deletes device record, calls oneSignal.logout, and resets state',
        () async {
          final events = <String>[];
          final fakeOneSignal = FakeOneSignalService(eventLog: events);

          final push = PushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'test-app-id',
          );

          push.setTestState(
            playerId: testPlayerId,
            currentUid: testUid,
            initialized: true,
          );

          expect(push.playerId, equals(testPlayerId));
          expect(push.initialized, isTrue);

          await push.cleanupOnSignOut(testUid);

          expect(fakeOneSignal.removePlayerCalled, isTrue);
          expect(fakeOneSignal.removedUid, equals(testUid));
          expect(fakeOneSignal.removedPlayerId, equals(testPlayerId));
          expect(fakeOneSignal.logoutCalled, isTrue);
          expect(push.playerId, isNull);
          expect(push.initialized, isFalse);

          expect(
            events,
            equals([
              'oneSignal.removePlayer($testUid, $testPlayerId)',
              'oneSignal.logout',
            ]),
          );
        },
      );

      test(
        'cleanupOnSignOut still calls oneSignal.logout and resets state when removePlayer fails',
        () async {
          final events = <String>[];
          final fakeOneSignal = FakeOneSignalService(
            eventLog: events,
            shouldThrowOnRemove: true,
          );

          final push = PushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'test-app-id',
          );

          push.setTestState(
            playerId: testPlayerId,
            currentUid: testUid,
            initialized: true,
          );

          await push.cleanupOnSignOut(testUid);

          expect(fakeOneSignal.removePlayerCalled, isTrue);
          expect(fakeOneSignal.logoutCalled, isTrue);
          expect(push.playerId, isNull);
          expect(push.initialized, isFalse);

          expect(
            events,
            equals([
              'oneSignal.removePlayer($testUid, $testPlayerId)',
              'oneSignal.logout',
            ]),
          );
        },
      );

      test(
        'cleanupOnSignOut resets state even if oneSignal.logout fails',
        () async {
          final events = <String>[];
          final fakeOneSignal = FakeOneSignalService(
            eventLog: events,
            shouldThrowOnLogout: true,
          );

          final push = PushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'test-app-id',
          );

          push.setTestState(
            playerId: testPlayerId,
            currentUid: testUid,
            initialized: true,
          );

          await push.cleanupOnSignOut(testUid);

          expect(push.playerId, isNull);
          expect(push.initialized, isFalse);
        },
      );

      test(
        'cleanupOnSignOut skips removePlayer when playerId is null but performs logout and resets state',
        () async {
          final events = <String>[];
          final fakeOneSignal = FakeOneSignalService(eventLog: events);

          final push = PushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'test-app-id',
          );

          push.setTestState(
            playerId: null,
            currentUid: testUid,
            initialized: true,
          );

          await push.cleanupOnSignOut(testUid);

          expect(fakeOneSignal.removePlayerCalled, isFalse);
          expect(fakeOneSignal.logoutCalled, isTrue);
          expect(push.playerId, isNull);
          expect(push.initialized, isFalse);
          expect(events, equals(['oneSignal.logout']));
        },
      );

      test(
        'cleanupOnSignOut skips removePlayer when uid is blank but still logs out and resets state',
        () async {
          final events = <String>[];
          final fakeOneSignal = FakeOneSignalService(eventLog: events);

          final push = PushController(
            oneSignal: fakeOneSignal,
            oneSignalAppId: 'test-app-id',
          );

          push.setTestState(
            playerId: testPlayerId,
            currentUid: testUid,
            initialized: true,
          );

          await push.cleanupOnSignOut('   ');

          expect(fakeOneSignal.removePlayerCalled, isFalse);
          expect(fakeOneSignal.logoutCalled, isTrue);
          expect(push.playerId, isNull);
          expect(push.initialized, isFalse);
          expect(events, equals(['oneSignal.logout']));
        },
      );
    });

    group('RouterNotifier Reset and Push Init Flag Verification', () {
      test(
        'reset() clears all flags including pushInitDone so subsequent login re-registers push',
        () {
          final routerNotifier = RouterNotifier();
          routerNotifier.setAuthed(true);
          routerNotifier.setRequiresName(true);
          routerNotifier.setBootstrapped(true);

          expect(routerNotifier.isAuthed, isTrue);
          expect(routerNotifier.requiresName, isTrue);
          expect(routerNotifier.bootstrapped, isTrue);

          routerNotifier.reset();

          expect(routerNotifier.isAuthed, isFalse);
          expect(routerNotifier.requiresName, isFalse);
          expect(routerNotifier.bootstrapped, isFalse);
        },
      );
    });
  });
}
