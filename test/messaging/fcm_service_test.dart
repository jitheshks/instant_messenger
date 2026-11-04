import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('FcmService Unit Tests (No Native Firebase SDK Required)', () {
    const testUserId = 'fcm-user-1111-2222-3333-444444444444';
    const testFcmToken =
        'fcm_token_sample_abc123_xyz789_long_registration_token_for_device';

    setUp(() {
      FcmService.onTap = null;
      FcmService.isChatOpenDelegate = null;
    });

    tearDown(() {
      FcmService.onTap = null;
      FcmService.isChatOpenDelegate = null;
    });

    group('Platform Normalization & Support', () {
      test('Normalizes standard supported platforms (case-insensitive)', () {
        expect(FcmService.normalizePlatform('android'), equals('android'));
        expect(FcmService.normalizePlatform('Android'), equals('android'));
        expect(FcmService.normalizePlatform('ANDROID'), equals('android'));
        expect(FcmService.normalizePlatform('ios'), equals('ios'));
        expect(FcmService.normalizePlatform('iOS'), equals('ios'));
        expect(FcmService.normalizePlatform('web'), equals('web'));
        expect(FcmService.normalizePlatform('WEB'), equals('web'));
      });

      test('Returns null for unsupported platforms', () {
        expect(FcmService.normalizePlatform(null), isNull);
        expect(FcmService.normalizePlatform(''), isNull);
        expect(FcmService.normalizePlatform('linux'), isNull);
        expect(FcmService.normalizePlatform('macos'), isNull);
        expect(FcmService.normalizePlatform('windows'), isNull);
        expect(FcmService.normalizePlatform('unknown'), isNull);
      });

      test(
        'isSupportedPlatform correctly identifies mobile and web targets only',
        () {
          expect(
            FcmService.isSupportedPlatform(
              targetPlatform: TargetPlatform.android,
            ),
            isTrue,
          );
          expect(
            FcmService.isSupportedPlatform(targetPlatform: TargetPlatform.iOS),
            isTrue,
          );
          expect(FcmService.isSupportedPlatform(isWeb: true), isTrue);
          expect(
            FcmService.isSupportedPlatform(
              targetPlatform: TargetPlatform.linux,
            ),
            isFalse,
          );
          expect(
            FcmService.isSupportedPlatform(
              targetPlatform: TargetPlatform.macOS,
            ),
            isFalse,
          );
          expect(
            FcmService.isSupportedPlatform(
              targetPlatform: TargetPlatform.windows,
            ),
            isFalse,
          );
        },
      );
    });

    group('Device Registration Payload Construction', () {
      test(
        'Builds valid payload matching user_devices schema with UTC ISO-8601 last_seen timestamp',
        () {
          final fixedTime = DateTime.utc(2026, 10, 26, 15, 30, 0);
          final payload = FcmService.buildDevicePayload(
            uid: testUserId,
            token: testFcmToken,
            platform: 'android',
            appVersion: '1.0.0+1',
            subscribed: true,
            timestamp: fixedTime,
          );

          expect(payload['user_id'], equals(testUserId));
          expect(payload['player_id'], equals(testFcmToken));
          expect(payload['platform'], equals('android'));
          expect(payload['app_version'], equals('1.0.0+1'));
          expect(payload['subscribed'], isTrue);
          expect(payload['last_seen'], equals('2026-10-26T15:30:00.000Z'));
        },
      );

      test('Omits empty or null app_version from payload', () {
        final payloadNull = FcmService.buildDevicePayload(
          uid: testUserId,
          token: testFcmToken,
          platform: 'ios',
          appVersion: null,
          subscribed: true,
        );
        expect(payloadNull.containsKey('app_version'), isFalse);
        expect(payloadNull['subscribed'], isTrue);

        final payloadEmpty = FcmService.buildDevicePayload(
          uid: testUserId,
          token: testFcmToken,
          platform: 'web',
          appVersion: '   ',
          subscribed: false,
        );
        expect(payloadEmpty.containsKey('app_version'), isFalse);
        expect(payloadEmpty['subscribed'], isFalse);
      });

      test('Throws ArgumentError for unsupported platform', () {
        expect(
          () => FcmService.buildDevicePayload(
            uid: testUserId,
            token: testFcmToken,
            platform: 'windows',
          ),
          throwsArgumentError,
        );
      });
    });

    group('Supabase Persistence & Conflict Target', () {
      test('Persists FCM token to user_devices with on_conflict=player_id', () async {
        var requestVerified = false;

        final mockHttp = MockClient((request) async {
          expect(request.url.path, contains('/rest/v1/user_devices'));
          expect(request.method, equals('POST'));

          final onConflictParam = request.url.queryParameters['on_conflict'];
          expect(onConflictParam, equals('player_id'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['user_id'], equals(testUserId));
          expect(body['player_id'], equals(testFcmToken));
          expect(body['platform'], equals('android'));
          expect(body['subscribed'], isTrue);

          requestVerified = true;
          return http.Response(
            jsonEncode({'message': 'Created'}),
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = FcmService(supabaseClient: client);

        final payload = FcmService.buildDevicePayload(
          uid: testUserId,
          token: testFcmToken,
          platform: 'android',
          appVersion: '1.0.0',
          subscribed: true,
        );

        final success = await service.persistDeviceRecord(payload);
        expect(success, isTrue);
        expect(requestVerified, isTrue);
      });

      test('Catches persistence failures gracefully and returns false', () async {
        final mockHttp = MockClient((request) async {
          return http.Response(
            jsonEncode({'message': 'Network unreachable'}),
            500,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = FcmService(supabaseClient: client);

        final payload = FcmService.buildDevicePayload(
          uid: testUserId,
          token: testFcmToken,
          platform: 'android',
        );

        final success = await service.persistDeviceRecord(payload);
        expect(success, isFalse);
      });
    });

    group('Foreground Notification Handling & In-App Suppression', () {
      test(
        'Suppresses local notification display when user is inside the targeted chat',
        () async {
          var displayCalled = false;
          FcmService.isChatOpenDelegate = (chatId) => chatId == 'chat-123';

          final mockHttp = MockClient((request) async {
            // RPC promote_message_status call
            return http.Response(
              jsonEncode({}),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          });

          final client = SupabaseClient(
            'https://mock.supabase.co',
            'mock-key',
            httpClient: mockHttp,
          );

          final service = FcmService(
            supabaseClient: client,
            notificationDisplayDelegate: ({
              required String chatId,
              required String title,
              required String body,
            }) async {
              displayCalled = true;
            },
          );

          final message = RemoteMessage(
            messageId: 'msg-abc-001',
            data: {
              'chatId': 'chat-123',
              'messageId': 'msg-abc-001',
              'senderName': 'Alice',
              'preview': 'Hello there!',
            },
          );

          await service.handleForegroundMessageForTesting(message);
          expect(displayCalled, isFalse);
        },
      );

      test(
        'Displays local notification when user is in a different chat or out of chat',
        () async {
          String? displayedChatId;
          String? displayedTitle;
          String? displayedBody;

          // Chat 'chat-999' is open, but incoming message is for 'chat-123'
          FcmService.isChatOpenDelegate = (chatId) => chatId == 'chat-999';

          final mockHttp = MockClient((request) async {
            return http.Response(
              jsonEncode({}),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          });

          final client = SupabaseClient(
            'https://mock.supabase.co',
            'mock-key',
            httpClient: mockHttp,
          );

          final service = FcmService(
            supabaseClient: client,
            notificationDisplayDelegate: ({
              required String chatId,
              required String title,
              required String body,
            }) async {
              displayedChatId = chatId;
              displayedTitle = title;
              displayedBody = body;
            },
          );

          final message = RemoteMessage(
            messageId: 'msg-abc-002',
            data: {
              'chatId': 'chat-123',
              'messageId': 'msg-abc-002',
              'senderName': 'Bob',
              'preview': 'Are you free?',
            },
          );

          await service.handleForegroundMessageForTesting(message);
          expect(displayedChatId, equals('chat-123'));
          expect(displayedTitle, equals('Bob'));
          expect(displayedBody, equals('Are you free?'));
        },
      );

      test('Promotes message status to delivered (2) via RPC in foreground for valid UUID messageId', () async {
        var rpcInvoked = false;
        const validUuid = 'b1e6701f-a136-4fb1-befb-8e9e23dcd12b';

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/rpc/promote_message_status')) {
            rpcInvoked = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['p_message_ids'], equals([validUuid]));
            expect(body['p_new_status'], equals(2));
          }
          return http.Response(
            jsonEncode({}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );

        final service = FcmService(
          supabaseClient: client,
          notificationDisplayDelegate: ({
            required String chatId,
            required String title,
            required String body,
          }) async {},
        );

        final message = const RemoteMessage(
          messageId: validUuid,
          data: {
            'chatId': 'chat-123',
            'messageId': validUuid,
          },
        );

        await service.handleForegroundMessageForTesting(message);
        expect(rpcInvoked, isTrue);
      });

      test('Ignores status promotion RPC when messageId is not a valid UUID', () async {
        var rpcInvoked = false;

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/rest/v1/rpc/promote_message_status')) {
            rpcInvoked = true;
          }
          return http.Response(
            jsonEncode({}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );

        final service = FcmService(
          supabaseClient: client,
          notificationDisplayDelegate: ({
            required String chatId,
            required String title,
            required String body,
          }) async {},
        );

        final message = const RemoteMessage(
          messageId: 'not-a-uuid-format',
          data: {
            'chatId': 'chat-123',
            'messageId': 'not-a-uuid-format',
          },
        );

        await service.handleForegroundMessageForTesting(message);
        expect(rpcInvoked, isFalse);
      });
    });

    group('Notification Tap Navigation (Cold & Warm Start)', () {
      test('Routes to chat via onTap callback when notification is tapped', () {
        String? tappedChatId;
        FcmService.onTap = (chatId) {
          tappedChatId = chatId;
        };

        final service = FcmService();
        final message = RemoteMessage(
          messageId: 'msg-tap-001',
          data: {'chatId': 'chat-target-456'},
        );

        service.handleNotificationTapForTesting(message);
        expect(tappedChatId, equals('chat-target-456'));
      });

      test('Accepts snake_case chat_id key in payload', () {
        String? tappedChatId;
        FcmService.onTap = (chatId) {
          tappedChatId = chatId;
        };

        final service = FcmService();
        final message = RemoteMessage(
          messageId: 'msg-tap-002',
          data: {'chat_id': 'chat-snake-case-789'},
        );

        service.handleNotificationTapForTesting(message);
        expect(tappedChatId, equals('chat-snake-case-789'));
      });

      test('Does nothing when notification data contains no valid chatId', () {
        var tapInvoked = false;
        FcmService.onTap = (chatId) {
          tapInvoked = true;
        };

        final service = FcmService();
        final message = RemoteMessage(
          messageId: 'msg-tap-empty',
          data: {'sender': 'Alice'},
        );

        service.handleNotificationTapForTesting(message);
        expect(tapInvoked, isFalse);
      });
    });

    group('Sign-Out Cleanup & Isolation', () {
      test('Deletes device record matching user_id and token from user_devices', () async {
        var deleteVerified = false;

        final mockHttp = MockClient((request) async {
          if (request.method == 'DELETE' &&
              request.url.path.contains('/rest/v1/user_devices')) {
            expect(request.url.queryParameters['user_id'], equals('eq.$testUserId'));
            expect(request.url.queryParameters['player_id'], equals('eq.$testFcmToken'));
            deleteVerified = true;
          }
          return http.Response(
            jsonEncode({}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );

        final service = FcmService(supabaseClient: client);
        service.setCurrentTokenForTesting(testFcmToken);
        service.setCurrentUidForTesting(testUserId);

        await service.cleanupOnSignOut(testUserId);

        expect(deleteVerified, isTrue);
        expect(service.currentToken, isNull);
        expect(service.isInitialized, isFalse);
      });
    });
  });
}
