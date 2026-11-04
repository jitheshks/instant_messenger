// test/calls/calling_foundation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/data/repositories/supabase_calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_invitation.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/call_rpc_result.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthSession implements Session {
  @override
  String get accessToken => 'mock-jwt-token';
  @override
  String get tokenType => 'bearer';
  @override
  User get user => const User(
    id: 'user-auth-1234',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoTrueClient implements GoTrueClient {
  Session? _session;
  User? _user;

  void setCurrentSession(Session? session, User? user) {
    _session = session;
    _user = user;
  }

  @override
  Session? get currentSession => _session;

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupabaseClient implements SupabaseClient {
  final _FakeGoTrueClient _auth = _FakeGoTrueClient();

  @override
  GoTrueClient get auth => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Call Enums & Lifecycle States', () {
    test('CallType serialization and deserialization', () {
      expect(CallType.audio.toJson(), 'audio');
      expect(CallType.video.toJson(), 'video');

      expect(CallType.fromJson('audio'), CallType.audio);
      expect(CallType.fromJson('video'), CallType.video);
      expect(CallType.fromJson('VIDEO'), CallType.video);
      expect(CallType.fromJson('unknown'), CallType.audio);
      expect(CallType.fromJson(null), CallType.audio);
    });

    test('CallStatus lifecycle progress and termination getters', () {
      expect(CallStatus.idle.isInProgress, isFalse);
      expect(CallStatus.idle.isTerminated, isTrue);

      expect(CallStatus.outgoing.isInProgress, isTrue);
      expect(CallStatus.outgoing.isTerminated, isFalse);

      expect(CallStatus.ringing.isInProgress, isTrue);
      expect(CallStatus.ringing.isTerminated, isFalse);

      expect(CallStatus.connecting.isInProgress, isTrue);
      expect(CallStatus.connecting.isTerminated, isFalse);

      expect(CallStatus.connected.isInProgress, isTrue);
      expect(CallStatus.connected.isTerminated, isFalse);

      expect(CallStatus.declined.isInProgress, isFalse);
      expect(CallStatus.declined.isTerminated, isTrue);

      expect(CallStatus.cancelled.isInProgress, isFalse);
      expect(CallStatus.cancelled.isTerminated, isTrue);

      expect(CallStatus.missed.isInProgress, isFalse);
      expect(CallStatus.missed.isTerminated, isTrue);

      expect(CallStatus.ended.isInProgress, isFalse);
      expect(CallStatus.ended.isTerminated, isTrue);

      expect(CallStatus.failed.isInProgress, isFalse);
      expect(CallStatus.failed.isTerminated, isTrue);
    });

    test('CallStatus serialization and deserialization', () {
      for (final status in CallStatus.values) {
        expect(CallStatus.fromJson(status.name), status);
        expect(CallStatus.fromJson(status.name.toUpperCase()), status);
      }
      expect(CallStatus.fromJson(null), CallStatus.idle);
      expect(CallStatus.fromJson('invalid_status'), CallStatus.idle);
    });
  });

  group('CallRecord Domain Model', () {
    final now = DateTime.now();

    test('toMap and fromMap roundtrip', () {
      final record = CallRecord(
        id: 'call-uuid-1',
        callerId: 'user-1',
        receiverId: 'user-2',
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 2, seconds: 15)),
        durationSeconds: 135,
        createdAt: now,
        updatedAt: now,
      );

      final map = record.toMap();
      final parsed = CallRecord.fromMap(map);

      expect(parsed.id, record.id);
      expect(parsed.callerId, record.callerId);
      expect(parsed.receiverId, record.receiverId);
      expect(parsed.callType, CallType.video);
      expect(parsed.status, CallStatus.ended);
      expect(parsed.durationSeconds, 135);
      expect(parsed.formattedDuration, '02:15');
      expect(parsed.isIncoming('user-2'), isTrue);
      expect(parsed.isIncoming('user-1'), isFalse);
      expect(parsed.isCompleted, isTrue);
      expect(parsed.isMissed, isFalse);
    });

    test('isMissed helper returns true for missed status', () {
      final record = CallRecord(
        id: 'call-uuid-2',
        callerId: 'user-1',
        receiverId: 'user-2',
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: now,
      );

      expect(record.isMissed, isTrue);
      expect(record.isCompleted, isFalse);
      expect(record.formattedDuration, '00:00');
    });

    test('copyWith updates specified fields', () {
      final record = CallRecord(
        id: 'call-uuid-3',
        callerId: 'user-1',
        receiverId: 'user-2',
        callType: CallType.audio,
        status: CallStatus.outgoing,
        startedAt: now,
      );

      final updated = record.copyWith(
        status: CallStatus.connected,
        durationSeconds: 60,
      );

      expect(updated.status, CallStatus.connected);
      expect(updated.durationSeconds, 60);
      expect(updated.id, record.id);
    });
  });

  group('CallInvitation Domain Model', () {
    final now = DateTime.now();

    test('toMap and fromMap roundtrip', () {
      final invitation = CallInvitation(
        callId: 'call-inv-1',
        callerId: 'user-1',
        callerName: 'Alice',
        callerAvatar: 'https://example.com/avatar.png',
        receiverId: 'user-2',
        callType: CallType.video,
        sentAt: now,
      );

      final map = invitation.toMap();
      final parsed = CallInvitation.fromMap(map);

      expect(parsed.callId, invitation.callId);
      expect(parsed.callerId, invitation.callerId);
      expect(parsed.callerName, 'Alice');
      expect(parsed.callerAvatar, 'https://example.com/avatar.png');
      expect(parsed.receiverId, invitation.receiverId);
      expect(parsed.callType, CallType.video);
    });
  });

  group('ZegoTokenResponse Model', () {
    test('parses valid JSON response', () {
      final json = {
        'token': '04sampletoken',
        'app_id': 12345678,
        'user_id': 'user-1234',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      };

      final response = ZegoTokenResponse.fromJson(json);
      expect(response.token, '04sampletoken');
      expect(response.appId, 12345678);
      expect(response.userId, 'user-1234');
      expect(response.isExpired, isFalse);
      expect(response.remainingSeconds > 0, isTrue);
    });

    test('throws FormatException on missing or invalid fields', () {
      expect(
        () => ZegoTokenResponse.fromJson({
          'token': '',
          'app_id': 1234,
          'user_id': 'user-1',
          'expires_at': 1000,
        }),
        throwsFormatException,
      );

      expect(
        () => ZegoTokenResponse.fromJson({
          'token': 'token',
          'app_id': 0,
          'user_id': 'user-1',
          'expires_at': 1000,
        }),
        throwsFormatException,
      );

      expect(
        () => ZegoTokenResponse.fromJson({
          'token': 'token',
          'app_id': 1234,
          'user_id': '',
          'expires_at': 1000,
        }),
        throwsFormatException,
      );

      expect(
        () => ZegoTokenResponse.fromJson({
          'token': 'token',
          'app_id': 1234,
          'user_id': 'user-1',
          'expires_at': 0,
        }),
        throwsFormatException,
      );
    });

    test('isExpired detects past expiration timestamp', () {
      final pastEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 100;
      final response = ZegoTokenResponse(
        token: 'token',
        appId: 1234,
        userId: 'user-1',
        expiresAt: pastEpoch,
      );

      expect(response.isExpired, isTrue);
      expect(response.remainingSeconds, 0);
    });
  });

  group('SupabaseCallsRepository Tests', () {
    late _FakeSupabaseClient fakeSupabase;

    setUp(() {
      fakeSupabase = _FakeSupabaseClient();
    });

    test(
      'throws CallsException(401) immediately when user is unauthenticated',
      () async {
        // No session set on fake auth
        fakeSupabase._auth.setCurrentSession(null, null);

        final repo = SupabaseCallsRepository(fakeSupabase);

        expect(
          () => repo.getZegoToken(),
          throwsA(
            isA<CallsException>().having(
              (e) => e.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
      },
    );

    test(
      'invokes get-zego-token with sanitized parameters and parses 200 response',
      () async {
        final mockUser = const User(
          id: 'user-auth-1234',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        );
        fakeSupabase._auth.setCurrentSession(_FakeAuthSession(), mockUser);

        Map<String, dynamic>? capturedBody;

        final repo = SupabaseCallsRepository(
          fakeSupabase,
          functionInvoker: (functionName, {headers, body}) async {
            expect(functionName, 'get-zego-token');
            capturedBody = body as Map<String, dynamic>?;
            return FunctionResponse(
              status: 200,
              data: {
                'token': '04mockedzegotoken',
                'app_id': 987654321,
                'user_id': 'user-auth-1234',
                'expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800,
              },
            );
          },
        );

        final result = await repo.getZegoToken(
          roomId: 'room-call-101',
          effectiveTimeInSeconds: 1800,
          callType: CallType.video,
        );

        expect(result.token, '04mockedzegotoken');
        expect(result.appId, 987654321);
        expect(result.userId, 'user-auth-1234');
        expect(result.isExpired, isFalse);

        // Verify captured payload matches requested values
        expect(capturedBody?['room_id'], 'room-call-101');
        expect(capturedBody?['effective_time_in_seconds'], 1800);
        expect(capturedBody?['call_type'], 'video');
        // Verify client did NOT send a spoofed user_id
        expect(capturedBody?.containsKey('user_id'), isFalse);
      },
    );

    test('handles String JSON response from Edge Function correctly', () async {
      fakeSupabase._auth.setCurrentSession(
        _FakeAuthSession(),
        const User(
          id: 'user-auth-1234',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );

      final repo = SupabaseCallsRepository(
        fakeSupabase,
        functionInvoker: (functionName, {headers, body}) async {
          return FunctionResponse(
            status: 200,
            data:
                '{"token":"04rawstringtoken","app_id":123456,"user_id":"user-auth-1234","expires_at":1800000000}',
          );
        },
      );

      final result = await repo.getZegoToken();
      expect(result.token, '04rawstringtoken');
      expect(result.appId, 123456);
      expect(result.userId, 'user-auth-1234');
    });

    test(
      'throws CallsException with error message when Edge Function returns error status',
      () async {
        fakeSupabase._auth.setCurrentSession(
          _FakeAuthSession(),
          const User(
            id: 'user-auth-1234',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01T00:00:00Z',
          ),
        );

        final repo = SupabaseCallsRepository(
          fakeSupabase,
          functionInvoker: (functionName, {headers, body}) async {
            return FunctionResponse(
              status: 500,
              data: {'error': 'Server configuration error'},
            );
          },
        );

        expect(
          () => repo.getZegoToken(),
          throwsA(
            isA<CallsException>()
                .having((e) => e.statusCode, 'statusCode', 500)
                .having(
                  (e) => e.message,
                  'message',
                  'Server configuration error',
                ),
          ),
        );
      },
    );

    test('throws CallsException on malformed response data', () async {
      fakeSupabase._auth.setCurrentSession(
        _FakeAuthSession(),
        const User(
          id: 'user-auth-1234',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );

      final repo = SupabaseCallsRepository(
        fakeSupabase,
        functionInvoker: (functionName, {headers, body}) async {
          return FunctionResponse(
            status: 200,
            data: [1, 2, 3], // Invalid array data instead of map
          );
        },
      );

      expect(() => repo.getZegoToken(), throwsA(isA<CallsException>()));
    });
  });

  group('CallRpcResult Domain Model Tests', () {
    test('parses successful initiate_call payload', () {
      final map = {
        'success': true,
        'call_id': 'c-123',
        'room_id': 'r-456',
        'call_type': 'video',
        'is_group': false,
        'status': 'ringing',
      };
      final res = CallRpcResult.fromMap(map);
      expect(res.success, isTrue);
      expect(res.callId, 'c-123');
      expect(res.roomId, 'r-456');
      expect(res.callType, 'video');
      expect(res.status, 'ringing');
      expect(res.errorCode, isNull);
    });

    test('parses conflict rejection payload (call_in_progress)', () {
      final map = {
        'success': false,
        'error': 'call_in_progress',
        'existing_call_id': 'c-busy-789',
      };
      final res = CallRpcResult.fromMap(map);
      expect(res.success, isFalse);
      expect(res.errorCode, 'call_in_progress');
      expect(res.existingCallId, 'c-busy-789');
      expect(res.callId, isNull);
      expect(res.roomId, isNull);
    });

    test('parses empty or unexpected map gracefully', () {
      final res = CallRpcResult.fromMap({});
      expect(res.success, isFalse);
      expect(res.callId, isNull);
      expect(res.errorCode, isNull);
    });
  });
}
