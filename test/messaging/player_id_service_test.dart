import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/features/notifications/data/player_id_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('PlayerIdService Supabase user_devices Migration Tests', () {
    const testUserId = '11111111-2222-3333-4444-555555555555';
    const peerUserId = '99999999-8888-7777-6666-555555555555';

    test(
      'Returns parsed and trimmed player IDs for matching user_id',
      () async {
        final mockHttp = MockClient((request) async {
          expect(request.url.path, contains('/rest/v1/user_devices'));
          expect(request.url.queryParameters['select'], equals('player_id'));
          expect(
            request.url.queryParameters['user_id'],
            equals('eq.$testUserId'),
          );

          final responseBody = jsonEncode([
            {'player_id': 'player-id-alpha'},
            {'player_id': 'player-id-beta'},
          ]);
          return http.Response(
            responseBody,
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
        final ids = await PlayerIdService.fetchPlayerIdsForUid(
          testUserId,
          client: client,
        );

        expect(ids, hasLength(2));
        expect(ids, containsAll(['player-id-alpha', 'player-id-beta']));
      },
    );

    test(
      'Deduplicates duplicate player IDs and ignores empty/null entries',
      () async {
        final mockHttp = MockClient((request) async {
          final responseBody = jsonEncode([
            {'player_id': 'player-unique-1'},
            {'player_id': 'player-unique-1'}, // Duplicate
            {'player_id': '  '}, // Whitespace
            {'player_id': null}, // Null
            {'player_id': 'player-unique-2 '}, // Needs trimming
          ]);
          return http.Response(
            responseBody,
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
        final ids = await PlayerIdService.fetchPlayerIdsForUid(
          testUserId,
          client: client,
        );

        expect(ids, hasLength(2));
        expect(ids, equals(['player-unique-1', 'player-unique-2']));
      },
    );

    test('Returns empty list when user has no registered devices', () async {
      final mockHttp = MockClient((request) async {
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
      final ids = await PlayerIdService.fetchPlayerIdsForUid(
        testUserId,
        client: client,
      );

      expect(ids, isEmpty);
    });

    test(
      'Returns empty list immediately when input uid is blank without issuing query',
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
        final emptyResult = await PlayerIdService.fetchPlayerIdsForUid(
          '',
          client: client,
        );
        final whitespaceResult = await PlayerIdService.fetchPlayerIdsForUid(
          '   ',
          client: client,
        );

        expect(emptyResult, isEmpty);
        expect(whitespaceResult, isEmpty);
        expect(requestMade, isFalse);
      },
    );

    test(
      'Catches query errors / non-200 responses and returns empty list gracefully',
      () async {
        final mockHttp = MockClient((request) async {
          return http.Response(
            jsonEncode({'message': 'Internal Server Error', 'code': '500'}),
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
        final ids = await PlayerIdService.fetchPlayerIdsForUid(
          testUserId,
          client: client,
        );

        expect(ids, isEmpty);
      },
    );

    test(
      'Simulates RLS authorization behavior: peer device query returns empty list under user_devices_all_self',
      () async {
        // In Supabase, the RLS policy "user_devices_all_self" specifies:
        //   for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)
        // When user A queries user B's devices, PostgREST filters out the records and returns 200 OK with [].
        final mockHttp = MockClient((request) async {
          final queriedUser = request.url.queryParameters['user_id'];
          if (queriedUser == 'eq.$peerUserId') {
            // RLS filter returns empty set for other users
            return http.Response(
              jsonEncode([]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          } else if (queriedUser == 'eq.$testUserId') {
            return http.Response(
              jsonEncode([
                {'player_id': 'own-device-id'},
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
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

        // Querying self returns registered tokens
        final selfIds = await PlayerIdService.fetchPlayerIdsForUid(
          testUserId,
          client: client,
        );
        expect(selfIds, equals(['own-device-id']));

        // Querying peer returns empty list due to RLS
        final peerIds = await PlayerIdService.fetchPlayerIdsForUid(
          peerUserId,
          client: client,
        );
        expect(peerIds, isEmpty);
      },
    );

    test(
      'Returns empty list when Supabase client is uninitialized without throwing uncaught exception',
      () async {
        // Without passing client, and when Supabase.instance is uninitialized, fetchPlayerIdsForUid catches and returns []
        final ids = await PlayerIdService.fetchPlayerIdsForUid('any-uid');
        expect(ids, isEmpty);
      },
    );
  });
}
