import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';

class MockOneSignalService extends OneSignalService {
  String? initializedAppId;
  String? initializedUid;
  bool initializeCalled = false;
  bool removePlayerCalled = false;
  String? removedUid;
  String? removedPlayerId;
  bool logoutCalled = false;
  String? stubbedPlayerId;

  MockOneSignalService({this.stubbedPlayerId})
      : super(null, null, null, () => true, () async {});

  @override
  bool get isPlatformSupported => true;

  @override
  Future<String?> initialize({
    required String appId,
    required String uid,
    bool promptPermission = true,
  }) async {
    initializeCalled = true;
    initializedAppId = appId;
    initializedUid = uid;
    return stubbedPlayerId;
  }

  @override
  Future<void> removePlayer(String uid, String playerId) async {
    removePlayerCalled = true;
    removedUid = uid;
    removedPlayerId = playerId;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

class MockFcmService extends FcmService {
  String? stubbedToken;
  bool initCalled = false;
  bool cleanupCalled = false;
  bool? capturedPersistToSupabase;

  MockFcmService({this.stubbedToken}) : super(platformChecker: () => true);

  @override
  bool get isPlatformSupported => true;

  @override
  Future<String?> init({
    required String uid,
    bool promptPermission = true,
    bool persistToSupabase = true,
  }) async {
    initCalled = true;
    capturedPersistToSupabase = persistToSupabase;
    return stubbedToken;
  }

  @override
  Future<void> cleanupOnSignOut(String uid) async {
    cleanupCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushController OneSignal-Only Architecture Tests', () {
    const testUid = 'user-1111-2222-3333-444444444444';
    const testOneSignalAppId = '70142ddd-32be-40e0-b1ce-97a1b958e3f4';
    const testPlayerId = '70142ddd-32be-40e0-b1ce-97a1b958e3f4';
    const testFcmToken = 'fcm_token_sample_abc123_xyz789_long_device_token';

    test('OneSignal subscription ID is NEVER removed when FCM token is acquired', () async {
      final mockOneSignal = MockOneSignalService(stubbedPlayerId: testPlayerId);
      final mockFcm = MockFcmService(stubbedToken: testFcmToken);

      final controller = PushController(
        oneSignal: mockOneSignal,
        oneSignalAppId: testOneSignalAppId,
        fcmService: mockFcm,
      );

      await controller.init(uid: testUid, promptPermission: false);

      expect(mockOneSignal.initializeCalled, isTrue);
      expect(mockOneSignal.initializedUid, equals(testUid));
      expect(mockFcm.initCalled, isTrue);
      expect(mockFcm.capturedPersistToSupabase, isFalse,
          reason: 'FCM tokens must not be persisted to user_devices in OneSignal-only architecture');

      // The critical fix: removePlayer MUST NOT be called!
      expect(mockOneSignal.removePlayerCalled, isFalse,
          reason: 'Obtaining an FCM token must NEVER delete the OneSignal subscription ID');

      expect(controller.playerId, equals(testPlayerId));
      expect(controller.fcmToken, equals(testFcmToken));
      expect(controller.initialized, isTrue);
    });

    test('Asynchronous subscription ID updates notify listeners and update playerId', () async {
      final mockOneSignal = MockOneSignalService(stubbedPlayerId: null);
      final controller = PushController(
        oneSignal: mockOneSignal,
        oneSignalAppId: testOneSignalAppId,
      );

      await controller.init(uid: testUid, promptPermission: false);
      expect(controller.playerId, isNull);

      var listenerNotified = false;
      controller.addListener(() {
        listenerNotified = true;
      });

      // Simulate OneSignal SDK observer firing when subscription ID is assigned
      mockOneSignal.onSubscriptionChanged?.call(testPlayerId);

      expect(controller.playerId, equals(testPlayerId));
      expect(listenerNotified, isTrue);
    });

    test('cleanupOnSignOut disassociates OneSignal and deletes device registration', () async {
      final mockOneSignal = MockOneSignalService(stubbedPlayerId: testPlayerId);
      final mockFcm = MockFcmService(stubbedToken: testFcmToken);

      final controller = PushController(
        oneSignal: mockOneSignal,
        oneSignalAppId: testOneSignalAppId,
        fcmService: mockFcm,
      );

      await controller.init(uid: testUid, promptPermission: false);
      expect(controller.playerId, equals(testPlayerId));

      await controller.cleanupOnSignOut(testUid);

      expect(mockOneSignal.removePlayerCalled, isTrue);
      expect(mockOneSignal.removedUid, equals(testUid));
      expect(mockOneSignal.removedPlayerId, equals(testPlayerId));
      expect(mockOneSignal.logoutCalled, isTrue);
      expect(mockFcm.cleanupCalled, isTrue);

      expect(controller.playerId, isNull);
      expect(controller.fcmToken, isNull);
      expect(controller.initialized, isFalse);
    });
  });

  group('OneSignalService.isValidSubscriptionId Validation', () {
    test('Validates RFC-4122 UUIDs as valid OneSignal subscription IDs', () {
      expect(OneSignalService.isValidSubscriptionId('70142ddd-32be-40e0-b1ce-97a1b958e3f4'), isTrue);
      expect(OneSignalService.isValidSubscriptionId('11111111-2222-3333-4444-555555555555'), isTrue);
    });

    test('Rejects invalid subscription IDs and raw FCM tokens', () {
      expect(OneSignalService.isValidSubscriptionId('player-uuid-001'), isFalse);
      expect(OneSignalService.isValidSubscriptionId(null), isFalse);
      expect(OneSignalService.isValidSubscriptionId(''), isFalse);
      expect(OneSignalService.isValidSubscriptionId('   '), isFalse);
      expect(OneSignalService.isValidSubscriptionId('token:with:colon'), isFalse);
      expect(
        OneSignalService.isValidSubscriptionId(
          'fcm_token_sample_abc123_xyz789_long_registration_token_for_device_1234567890_abcdefghij',
        ),
        isFalse,
      );
      expect(
        OneSignalService.isValidSubscriptionId('a' * 150),
        isFalse,
      );
    });
  });
}
