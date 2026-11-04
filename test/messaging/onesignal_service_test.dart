import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('OneSignalService Unit Tests (No Native SDK Required)', () {
    const testUserId = '11111111-2222-3333-4444-555555555555';
    const testPlayerId = '70142ddd-32be-40e0-b1ce-97a1b958e3f4';

    group('Platform Normalization', () {
      test('Normalizes standard supported platforms (case-insensitive)', () {
        expect(
          OneSignalService.normalizePlatform('android'),
          equals('android'),
        );
        expect(
          OneSignalService.normalizePlatform('Android'),
          equals('android'),
        );
        expect(
          OneSignalService.normalizePlatform('ANDROID'),
          equals('android'),
        );
        expect(OneSignalService.normalizePlatform('ios'), equals('ios'));
        expect(OneSignalService.normalizePlatform('iOS'), equals('ios'));
        expect(OneSignalService.normalizePlatform('web'), equals('web'));
        expect(OneSignalService.normalizePlatform('WEB'), equals('web'));
      });

      test(
        'Returns null for unsupported, unknown, or null platforms (does not classify as android)',
        () {
          expect(OneSignalService.normalizePlatform(null), isNull);
          expect(OneSignalService.normalizePlatform(''), isNull);
          expect(OneSignalService.normalizePlatform('unknown'), isNull);
          expect(
            OneSignalService.normalizePlatform('TargetPlatform.linux'),
            isNull,
          );
          expect(OneSignalService.normalizePlatform('linux'), isNull);
          expect(OneSignalService.normalizePlatform('macos'), isNull);
          expect(OneSignalService.normalizePlatform('windows'), isNull);
          expect(OneSignalService.normalizePlatform('fuchsia'), isNull);
        },
      );

      test(
        'isSupportedPlatform correctly identifies mobile and web targets only',
        () {
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.android,
            ),
            isTrue,
          );
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.iOS,
            ),
            isTrue,
          );
          expect(OneSignalService.isSupportedPlatform(isWeb: true), isTrue);
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.linux,
            ),
            isFalse,
          );
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.macOS,
            ),
            isFalse,
          );
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.windows,
            ),
            isFalse,
          );
          expect(
            OneSignalService.isSupportedPlatform(
              targetPlatform: TargetPlatform.fuchsia,
            ),
            isFalse,
          );
        },
      );
    });

    group('Subscribed State Computation', () {
      test(
        'Returns true only when opted in and permission is granted or not explicitly denied',
        () {
          expect(
            OneSignalService.computeSubscribed(optedIn: true, permission: true),
            isTrue,
          );
          expect(
            OneSignalService.computeSubscribed(optedIn: true, permission: null),
            isTrue,
          );
        },
      );

      test(
        'Returns false when opted out even if system permission is granted',
        () {
          expect(
            OneSignalService.computeSubscribed(
              optedIn: false,
              permission: true,
            ),
            isFalse,
          );
        },
      );

      test(
        'Returns false when system permission is denied even if opted in',
        () {
          expect(
            OneSignalService.computeSubscribed(
              optedIn: true,
              permission: false,
            ),
            isFalse,
          );
        },
      );

      test('Returns false when opted in is null or indeterminate', () {
        expect(
          OneSignalService.computeSubscribed(optedIn: null, permission: true),
          isFalse,
        );
        expect(
          OneSignalService.computeSubscribed(optedIn: null, permission: false),
          isFalse,
        );
        expect(
          OneSignalService.computeSubscribed(optedIn: null, permission: null),
          isFalse,
        );
      });
    });

    group('Device Registration Payload Construction', () {
      test(
        'Builds valid payload matching local contract with UTC ISO-8601 last_seen timestamp',
        () {
          final fixedTime = DateTime.utc(2026, 10, 22, 12, 34, 56);
          final payload = OneSignalService.buildDevicePayload(
            uid: testUserId,
            playerId: testPlayerId,
            platform: 'iOS',
            appVersion: '2.1.0+42',
            subscribed: true,
            timestamp: fixedTime,
          );

          expect(payload['user_id'], equals(testUserId));
          expect(payload['player_id'], equals(testPlayerId));
          expect(payload['platform'], equals('ios'));
          expect(payload['app_version'], equals('2.1.0+42'));
          expect(payload['subscribed'], isTrue);
          expect(payload['last_seen'], equals('2026-10-22T12:34:56.000Z'));
        },
      );

      test('Omits empty or null app_version from payload', () {
        final payloadNull = OneSignalService.buildDevicePayload(
          uid: testUserId,
          playerId: testPlayerId,
          platform: 'android',
          appVersion: null,
          subscribed: false,
        );
        expect(payloadNull.containsKey('app_version'), isFalse);
        expect(payloadNull['subscribed'], isFalse);

        final payloadEmpty = OneSignalService.buildDevicePayload(
          uid: testUserId,
          playerId: testPlayerId,
          platform: 'web',
          appVersion: '   ',
          subscribed: true,
        );
        expect(payloadEmpty.containsKey('app_version'), isFalse);
      });
    });

    group('Supabase Persistence & Conflict Handling', () {
      test('Persists device record with conflict target (player_id)', () async {
        var requestVerified = false;

        final mockHttp = MockClient((request) async {
          expect(request.url.path, contains('/rest/v1/rpc/register_device'));
          expect(request.method, equals('POST'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_player_id'], equals(testPlayerId));
          expect(body['p_platform'], equals('android'));
          expect(body['p_subscribed'], isTrue);

          requestVerified = true;
          return http.Response(
            jsonEncode({'message': 'Created'}),
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
        final service = OneSignalService(null, null, client);

        final payload = OneSignalService.buildDevicePayload(
          uid: testUserId,
          playerId: testPlayerId,
          platform: 'android',
          appVersion: '1.0.0',
          subscribed: true,
        );

        final success = await service.persistDeviceRecord(payload);
        expect(success, isTrue);
        expect(requestVerified, isTrue);
      });

      test(
        'Catches persistence failures gracefully and returns false without rethrowing',
        () async {
          final mockHttp = MockClient((request) async {
            return http.Response(
              jsonEncode({
                'message': 'Database connection lost',
                'code': '500',
              }),
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
          final service = OneSignalService(null, null, client);

          final payload = OneSignalService.buildDevicePayload(
            uid: testUserId,
            playerId: testPlayerId,
            platform: 'android',
            appVersion: '1.0.0',
            subscribed: true,
          );

          final success = await service.persistDeviceRecord(payload);
          expect(success, isFalse);
        },
      );
    });

    group('Device Removal & Query Ownership Filters', () {
      test(
        'Removes player applying exact user_id and player_id equality filters',
        () async {
          var deleteVerified = false;

          final mockHttp = MockClient((request) async {
            expect(request.url.path, contains('/rest/v1/user_devices'));
            expect(request.method, equals('DELETE'));
            expect(
              request.url.queryParameters['user_id'],
              equals('eq.$testUserId'),
            );
            expect(
              request.url.queryParameters['player_id'],
              equals('eq.$testPlayerId'),
            );

            deleteVerified = true;
            return http.Response(
              jsonEncode([]),
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
          final service = OneSignalService(null, null, client);

          await service.removePlayer(testUserId, testPlayerId);
          expect(deleteVerified, isTrue);
        },
      );

      test(
        'Catches removal failures without throwing uncaught exceptions',
        () async {
          final mockHttp = MockClient((request) async {
            return http.Response(
              jsonEncode({
                'message': 'Row Level Security policy violation',
                'code': '42501',
              }),
              403,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          });

          final client = SupabaseClient(
            'https://mock.supabase.co',
            'mock-key',
            httpClient: mockHttp,
          );
          final service = OneSignalService(null, null, client);

          // Does not throw
          await expectLater(
            service.removePlayer(testUserId, testPlayerId),
            completes,
          );
        },
      );

      test(
        'Skips removePlayer when uid or playerId is blank without issuing HTTP request',
        () async {
          var requestMade = false;
          final mockHttp = MockClient((request) async {
            requestMade = true;
            return http.Response('[]', 200, request: request);
          });

          final client = SupabaseClient(
            'https://mock.supabase.co',
            'mock-key',
            httpClient: mockHttp,
          );
          final service = OneSignalService(null, null, client);

          await service.removePlayer('', testPlayerId);
          await service.removePlayer(testUserId, '  ');
          await service.removePlayer('   ', '');

          expect(requestMade, isFalse);
        },
      );
    });

    group('OneSignalService Lifecycle & Logout', () {
      test(
        'Skips initialize on unsupported platform without throwing',
        () async {
          final service = OneSignalService(
            null,
            null,
            null,
            () => false, // Platform unsupported (e.g. desktop)
          );

          final result = await service.initialize(
            appId: 'test-app-id',
            uid: testUserId,
          );

          expect(result, isNull);
        },
      );

      test('Calls custom logout callback and completes cleanly', () async {
        var logoutCalled = false;
        final service = OneSignalService(null, null, null, null, () async {
          logoutCalled = true;
        });

        await service.logout();
        expect(logoutCalled, isTrue);
      });

      test('Catches logout exceptions gracefully without rethrowing', () async {
        final service = OneSignalService(
          null,
          null,
          null,
          null,
          () async => throw Exception('Native OneSignal logout crashed'),
        );

        await expectLater(service.logout(), completes);
      });
    });
  });
}
