import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:instant_messenger/features/notifications/data/background_delivery_ack_service.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testSupabaseUrl = 'https://xyzproject.supabase.co';
  const testAnonKey = 'anon-public-key-sample-12345';
  const testUserId = 'a0000000-0000-0000-0000-000000000099';
  const testMessageId = 'a0000000-0000-0000-0000-000000000001';
  const testReceiptToken = 'rt-test-token-abcdef';

  setUp(() {
    BackgroundDeliveryAckService.clearRecentAcksForTesting();
    AppConfig.overrideForTesting(
      const AppConfig(
        supabaseUrl: testSupabaseUrl,
        supabasePublishableKey: testAnonKey,
      ),
    );
  });

  tearDown(() {
    AppConfig.resetForTesting();
    BackgroundDeliveryAckService.clearRecentAcksForTesting();
  });

  Map<String, dynamic> createTestSession({
    String accessToken = 'valid-jwt-token-123',
    String refreshToken = 'refresh-token-456',
    int? expiresAt,
    String userId = testUserId,
  }) {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': 'bearer',
      'expires_at': expiresAt ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600),
      'user': {
        'id': userId,
        'email': 'user@example.com',
      },
    };
  }

  group('BackgroundDeliveryAckService Hardened Unit & Isolate Tests', () {
    test('1. Valid FCM payload is parsed and acknowledged correctly', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      http.Request? capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        if (request.url.path.contains('/rest/v1/rpc/acknowledge_delivery_token')) {
          return http.Response('true', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not found', 404);
      });

      final payload = {
        'chatId': 'c0000000-0000-0000-0000-000000000001',
        'messageId': testMessageId,
        'receiptToken': testReceiptToken,
        'recipientId': testUserId,
      };

      final result = await BackgroundDeliveryAckService.acknowledgeFromPayload(
        payload,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isTrue);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.toString(), '$testSupabaseUrl/rest/v1/rpc/acknowledge_delivery_token');
      expect(capturedRequest!.headers['apikey'], testAnonKey);
      expect(capturedRequest!.headers['authorization'], 'Bearer valid-jwt-token-123');

      final body = jsonDecode(capturedRequest!.body);
      expect(body['p_message_id'], testMessageId);
      expect(body['p_receipt_token'], testReceiptToken);
    });

    test('2. Missing message ID is handled safely without throwing', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = await BackgroundDeliveryAckService.acknowledgeFromPayload(
        {
          'receiptToken': testReceiptToken,
        },
        preferences: prefs,
      );

      expect(result, isFalse);
    });

    test('3. Missing delivery token is handled safely without throwing', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = await BackgroundDeliveryAckService.acknowledgeFromPayload(
        {
          'messageId': testMessageId,
        },
        preferences: prefs,
      );

      expect(result, isFalse);
    });

    test('4. Malformed messageId (non-UUID) does not crash and returns false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final result = await BackgroundDeliveryAckService.acknowledgeFromPayload(
        {
          'messageId': 'not-a-valid-uuid',
          'receiptToken': testReceiptToken,
        },
        preferences: prefs,
      );

      expect(result, isFalse);
    });

    test('5. Supports snake_case FCM payload keys safely', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeFromPayload(
        {
          'chat_id': 'c0000000-0000-0000-0000-000000000001',
          'message_id': testMessageId,
          'receipt_token': testReceiptToken,
          'recipient_id': testUserId,
        },
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isTrue);
      expect(rpcCalled, isTrue);
    });

    test('6. Missing authentication session (logged out) is handled safely', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        // No session stored
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      expect(rpcCalled, isFalse);
    });

    test('7. Recipient mismatch rejection: push intended for another user returns false', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession(userId: testUserId)),
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        expectedRecipientId: 'b0000000-0000-0000-0000-000000000099', // Different user
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      expect(rpcCalled, isFalse);
    });

    test('8. SEC-FCM-01: Expired access token returns false without sending a refresh request', () async {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final expiredSession = createTestSession(
        accessToken: 'expired-access-token',
        refreshToken: 'valid-refresh-token',
        expiresAt: nowSec - 100, // Expired in the past
      );

      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(expiredSession),
      });
      final prefs = await SharedPreferences.getInstance();

      bool networkCalled = false;
      final mockClient = MockClient((request) async {
        networkCalled = true;
        return http.Response('Not found', 404);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      // Must return false cleanly without hitting either /auth/v1/token or /rest/v1/rpc
      expect(result, isFalse);
      expect(networkCalled, isFalse);
    });

    test('9. SEC-FCM-01: No refresh token is rotated or written to SharedPreferences on expired session', () async {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final originalSessionJson = jsonEncode(createTestSession(
        accessToken: 'expired-access-token',
        refreshToken: 'pristine-refresh-token-do-not-touch',
        expiresAt: nowSec - 10,
      ));

      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': originalSessionJson,
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        fail('No network request should be dispatched when token is expired');
      });

      await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      // Verify that SharedPreferences session was untouched (not mutated or deleted)
      expect(prefs.getString('sb-xyzproject-auth-token'), originalSessionJson);
    });

    test('10. SEC-FCM-02: HTTP 200 with body false returns false and does NOT record message ID in LRU cache', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        return http.Response('false', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      // Verify message ID was NOT added to the cache
      expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isFalse);
    });

    test('11. SEC-FCM-02: Repeating a previously rejected message ID dispatches network and does not falsely return true', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      int calls = 0;
      final mockClient = MockClient((request) async {
        calls++;
        return http.Response('false', 200);
      });

      // First attempt fails at server
      final first = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );
      expect(first, isFalse);
      expect(calls, 1);

      // Second attempt must NOT be short-circuited as true by LRU cache
      final second = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );
      expect(second, isFalse);
      expect(calls, 2); // Dispatched to server again!
    });

    test('12. SEC-FCM-02: Unexpected response bodies (e.g. empty, null, error JSON) are not cached as success', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      for (final badBody in ['', 'null', '{"error":"some_error"}', 'undefined']) {
        final mockClient = MockClient((request) async {
          return http.Response(badBody, 200);
        });

        final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
          messageId: testMessageId,
          receiptToken: testReceiptToken,
          httpClient: mockClient,
          preferences: prefs,
        );

        expect(result, isFalse);
        expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isFalse);
      }
    });

    test('13. SEC-FCM-02: Duplicate notification deduplication: HTTP 200 with body true records cache and skips second request', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      int httpCalls = 0;
      final mockClient = MockClient((request) async {
        httpCalls++;
        return http.Response('true', 200);
      });

      final firstResult = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(firstResult, isTrue);
      expect(httpCalls, 1);
      expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isTrue);

      // Second identical call skips network
      final secondResult = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(secondResult, isTrue);
      expect(httpCalls, 1);
    });

    test('14. Deduplication cache LRU bound (max 200 items)', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        return http.Response('true', 200);
      });

      // Fill cache with 200 items
      for (int i = 0; i < 200; i++) {
        final id = 'a0000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
        await BackgroundDeliveryAckService.acknowledgeDelivery(
          messageId: id,
          receiptToken: 'token-$i',
          httpClient: mockClient,
          preferences: prefs,
        );
      }

      expect(BackgroundDeliveryAckService.recentAcksForTesting.length, 200);
      expect(
        BackgroundDeliveryAckService.recentAcksForTesting.contains(
          'a0000000-0000-0000-0000-000000000000',
        ),
        isTrue,
      );

      // Add 201st item
      await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: 'a0000000-0000-0000-0000-000000000201',
        receiptToken: 'token-201',
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(BackgroundDeliveryAckService.recentAcksForTesting.length, 200);
      // Oldest entry (index 0) was evicted
      expect(
        BackgroundDeliveryAckService.recentAcksForTesting.contains(
          'a0000000-0000-0000-0000-000000000000',
        ),
        isFalse,
      );
      expect(
        BackgroundDeliveryAckService.recentAcksForTesting.contains(
          'a0000000-0000-0000-0000-000000000201',
        ),
        isTrue,
      );
    });

    test('15. Network timeout is handled gracefully and returns false without caching', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        throw TimeoutException('Simulated 5s network timeout');
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isFalse);
    });

    test('16. Supabase authorization error (401/403) returns false safely without caching', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': '42501 Unauthorized: caller must be authenticated'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isFalse);
    });

    test('17. Network socket exception is handled safely and returns false without caching', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        throw const SocketException('Failed host lookup');
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isFalse);
      expect(BackgroundDeliveryAckService.recentAcksForTesting.contains(testMessageId), isFalse);
    });

    test('18. SEC-FCM-03: Resolves session stored under deterministic flutter.-prefixed project key', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.supabase_url': testSupabaseUrl,
        'flutter.supabase_anon_key': testAnonKey,
        'flutter.sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isTrue);
      expect(rpcCalled, isTrue);
    });

    test('19. SEC-FCM-03: Deterministic project session selection never selects an arbitrary session from another project', () async {
      // Setup: Current URL is for "xyzproject", but SharedPreferences ONLY contains tokens for "otherproject" and "stagingproject"
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-otherproject-auth-token': jsonEncode(createTestSession(accessToken: 'other-jwt')),
        'sb-stagingproject-auth-token': jsonEncode(createTestSession(accessToken: 'staging-jwt')),
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      final result = await BackgroundDeliveryAckService.acknowledgeDelivery(
        messageId: testMessageId,
        receiptToken: testReceiptToken,
        httpClient: mockClient,
        preferences: prefs,
      );

      // Must abort cleanly without bleeding into other project sessions
      expect(result, isFalse);
      expect(rpcCalled, isFalse);
    });

    test('20. acknowledgeFromRemoteMessage extracts RemoteMessage and acknowledges', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });
      final prefs = await SharedPreferences.getInstance();

      bool rpcCalled = false;
      final mockClient = MockClient((request) async {
        rpcCalled = true;
        return http.Response('true', 200);
      });

      const message = RemoteMessage(
        messageId: 'fcm-msg-id-12345',
        data: {
          'messageId': testMessageId,
          'receiptToken': testReceiptToken,
          'recipientId': testUserId,
        },
      );

      final result = await BackgroundDeliveryAckService.acknowledgeFromRemoteMessage(
        message,
        httpClient: mockClient,
        preferences: prefs,
      );

      expect(result, isTrue);
      expect(rpcCalled, isTrue);
    });

    test('21. firebaseMessagingBackgroundHandler does not throw uninitialized Supabase assertion', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': testSupabaseUrl,
        'supabase_anon_key': testAnonKey,
        'sb-xyzproject-auth-token': jsonEncode(createTestSession()),
      });

      const message = RemoteMessage(
        messageId: 'fcm-msg-id-999',
        data: {
          'messageId': testMessageId,
          'receiptToken': testReceiptToken,
          'recipientId': testUserId,
        },
      );

      await expectLater(
        firebaseMessagingBackgroundHandler(message),
        completes,
      );
    });

    test('22. Log hygiene: Secret tokens and keys are never logged in cleartext', () async {
      final logs = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      try {
        SharedPreferences.setMockInitialValues({
          'supabase_url': testSupabaseUrl,
          'supabase_anon_key': testAnonKey,
          'sb-xyzproject-auth-token': jsonEncode(createTestSession(
            accessToken: 'super-secret-jwt-token-abcdef',
            refreshToken: 'super-secret-refresh-token-12345',
          )),
        });
        final prefs = await SharedPreferences.getInstance();

        final mockClient = MockClient((request) async {
          return http.Response('401 Unauthorized', 401);
        });

        await BackgroundDeliveryAckService.acknowledgeDelivery(
          messageId: testMessageId,
          receiptToken: 'ultra-sensitive-receipt-token-777',
          httpClient: mockClient,
          preferences: prefs,
        );

        final joinedLogs = logs.join('\n');
        expect(joinedLogs.contains('super-secret-jwt-token-abcdef'), isFalse);
        expect(joinedLogs.contains('super-secret-refresh-token-12345'), isFalse);
        expect(joinedLogs.contains('ultra-sensitive-receipt-token-777'), isFalse);
      } finally {
        debugPrint = originalPrint;
      }
    });
  });
}
