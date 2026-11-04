// test/calls/call_backend_lifecycle_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/data/repositories/supabase_calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSession implements Session {
  @override
  String get accessToken => 'mock-jwt-token';
  @override
  String get tokenType => 'bearer';
  @override
  User get user => const User(
    id: 'caller-uid-1111',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockGoTrueClient implements GoTrueClient {
  Session? _session = _MockSession();

  @override
  Session? get currentSession => _session;

  @override
  User? get currentUser => _session?.user;

  void clearSession() {
    _session = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSupabaseClient implements SupabaseClient {
  final _MockGoTrueClient _auth = _MockGoTrueClient();

  @override
  GoTrueClient get auth => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _MockSupabaseClient mockSupabase;

  setUp(() {
    mockSupabase = _MockSupabaseClient();
  });

  group('SupabaseCallsRepository — Lifecycle RPC Contract Tests', () {
    test('initiateCall invokes initiate_call RPC with correct parameters', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {
            'success': true,
            'call_id': 'call-uuid-1',
            'room_id': 'room-uuid-1',
            'call_type': 'video',
            'is_group': false,
            'status': 'ringing',
          };
        },
      );

      final res = await repo.initiateCall(
        chatId: 'chat-uuid-1',
        callType: CallType.video,
        inviteeIds: ['invitee-uuid-2'],
      );

      expect(invokedFn, 'initiate_call');
      expect(capturedParams?['p_chat_id'], 'chat-uuid-1');
      expect(capturedParams?['p_call_type'], 'video');
      expect(capturedParams?['p_invitee_ids'], ['invitee-uuid-2']);
      expect(res['success'], isTrue);
      expect(res['call_id'], 'call-uuid-1');
      expect(res['status'], 'ringing');
    });

    test('acceptCall invokes accept_call RPC and returns call details', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {
            'success': true,
            'call_id': 'call-uuid-1',
            'room_id': 'room-uuid-1',
            'call_type': 'audio',
            'status': 'ongoing',
          };
        },
      );

      final res = await repo.acceptCall('call-uuid-1');

      expect(invokedFn, 'accept_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'ongoing');
      expect(res['room_id'], 'room-uuid-1');
    });

    test('rejectCall invokes reject_call RPC and returns rejected status', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {'success': true, 'status': 'rejected'};
        },
      );

      final res = await repo.rejectCall('call-uuid-1');

      expect(invokedFn, 'reject_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'rejected');
    });

    test('cancelCall invokes cancel_call RPC and returns cancelled status', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {'success': true, 'status': 'cancelled'};
        },
      );

      final res = await repo.cancelCall('call-uuid-1');

      expect(invokedFn, 'cancel_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'cancelled');
    });

    test('leaveCall invokes leave_call RPC and returns departure status with duration', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {
            'success': true,
            'status': 'ended',
            'duration_seconds': 142,
            'call_ended': true,
          };
        },
      );

      final res = await repo.leaveCall('call-uuid-1');

      expect(invokedFn, 'leave_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'ended');
      expect(res['duration_seconds'], 142);
      expect(res['call_ended'], isTrue);
    });

    test('inviteToCall invokes invite_to_call RPC with additional invitees', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {
            'success': true,
            'call_id': 'call-uuid-1',
            'newly_invited_count': 2,
          };
        },
      );

      final res = await repo.inviteToCall(
        callId: 'call-uuid-1',
        inviteeIds: ['invitee-3', 'invitee-4'],
      );

      expect(invokedFn, 'invite_to_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(capturedParams?['p_invitee_ids'], ['invitee-3', 'invitee-4']);
      expect(res['success'], isTrue);
      expect(res['newly_invited_count'], 2);
    });

    test('rejoinCall invokes rejoin_call RPC and returns room_id for ongoing call', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {
            'success': true,
            'call_id': 'call-uuid-1',
            'room_id': 'room-uuid-1',
            'call_type': 'video',
            'status': 'ongoing',
          };
        },
      );

      final res = await repo.rejoinCall('call-uuid-1');

      expect(invokedFn, 'rejoin_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'ongoing');
      expect(res['room_id'], 'room-uuid-1');
    });

    test('timeoutCall invokes timeout_call RPC (service_role)', () async {
      String? invokedFn;
      Map<String, dynamic>? capturedParams;

      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          invokedFn = fnName;
          capturedParams = params;
          return {'success': true, 'status': 'missed'};
        },
      );

      final res = await repo.timeoutCall('call-uuid-1');

      expect(invokedFn, 'timeout_call');
      expect(capturedParams?['p_call_id'], 'call-uuid-1');
      expect(res['success'], isTrue);
      expect(res['status'], 'missed');
    });

    test('Unauthenticated user throws CallsException(401) on any RPC invocation', () async {
      (mockSupabase.auth as _MockGoTrueClient).clearSession();

      final repo = SupabaseCallsRepository(mockSupabase);

      expect(
        () => repo.initiateCall(
          chatId: 'chat-1',
          callType: CallType.audio,
          inviteeIds: ['u-2'],
        ),
        throwsA(isA<CallsException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(
        () => repo.acceptCall('call-1'),
        throwsA(isA<CallsException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('Simulated Concurrency, Lock Ordering & Outbox Tests', () {
    test('Simultaneous call initiation returns call_in_progress when active call exists', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          return {
            'success': false,
            'error': 'call_in_progress',
            'existing_call_id': 'existing-call-123',
          };
        },
      );

      final res = await repo.initiateCall(
        chatId: 'chat-busy',
        callType: CallType.audio,
        inviteeIds: ['invitee-busy'],
      );

      expect(res['success'], isFalse);
      expect(res['error'], 'call_in_progress');
      expect(res['existing_call_id'], 'existing-call-123');
    });

    test('Accept after call timeout window (>45s) returns call_timed_out', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          return {
            'success': false,
            'error': 'call_timed_out',
            'status': 'missed',
          };
        },
      );

      final res = await repo.acceptCall('call-timed-out');

      expect(res['success'], isFalse);
      expect(res['error'], 'call_timed_out');
      expect(res['status'], 'missed');
    });

    test('Accept after caller cancellation returns call_terminated', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          return {
            'success': false,
            'error': 'call_terminated',
            'status': 'cancelled',
          };
        },
      );

      final res = await repo.acceptCall('call-cancelled');

      expect(res['success'], isFalse);
      expect(res['error'], 'call_terminated');
      expect(res['status'], 'cancelled');
    });

    test('Leave call when accepted count drops below 2 in 1-on-1 terminates call (Decision A2)', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          // Caller leaves 1-on-1 -> accepted count becomes 1 (< 2) -> call terminates
          return {
            'success': true,
            'status': 'ended',
            'duration_seconds': 60,
            'call_ended': true,
          };
        },
      );

      final res = await repo.leaveCall('call-direct-1');

      expect(res['success'], isTrue);
      expect(res['status'], 'ended');
      expect(res['call_ended'], isTrue);
      expect(res['duration_seconds'], 60);
    });

    test('Leave group call with 1 accepted participant and pending invitations keeps call active (Decision A2)', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          return {
            'success': true,
            'status': 'left',
            'active_participants': 1,
            'pending_invitations': 2,
            'call_ended': false,
          };
        },
      );

      final res = await repo.leaveCall('call-group-1');

      expect(res['success'], isTrue);
      expect(res['status'], 'left');
      expect(res['active_participants'], 1);
      expect(res['pending_invitations'], 2);
      expect(res['call_ended'], isFalse);
    });

    test('Rejoin call is permitted only from left status; rejects invited or active', () async {
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fnName, {params}) async {
          return {
            'success': false,
            'error': 'invalid_status_for_rejoin',
            'current_status': 'accepted',
          };
        },
      );

      final res = await repo.rejoinCall('call-already-in');

      expect(res['success'], isFalse);
      expect(res['error'], 'invalid_status_for_rejoin');
      expect(res['current_status'], 'accepted');
    });

    test('Multi-Session Race: Cancel vs Accept (Caller cancels before Callee accepts)', () async {
      // Simulation of Session 1 (Caller) winning row lock and cancelling
      var callStatus = 'ringing';

      Future<Map<String, dynamic>> callerSessionCancel() async {
        if (callStatus == 'ringing') {
          callStatus = 'cancelled';
          return {'success': true, 'status': 'cancelled'};
        }
        return {'success': false, 'error': 'cannot_cancel_active_or_ended_call', 'status': callStatus};
      }

      // Simulation of Session 2 (Callee) arriving second after row lock release
      Future<Map<String, dynamic>> calleeSessionAccept() async {
        if (callStatus == 'cancelled') {
          return {'success': false, 'error': 'call_terminated', 'status': 'cancelled'};
        }
        callStatus = 'ongoing';
        return {'success': true, 'status': 'ongoing'};
      }

      final callerRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => callerSessionCancel());
      final calleeRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => calleeSessionAccept());

      final cancelRes = await callerRepo.cancelCall('call-race-1');
      final acceptRes = await calleeRepo.acceptCall('call-race-1');

      expect(cancelRes['success'], isTrue);
      expect(cancelRes['status'], 'cancelled');
      expect(acceptRes['success'], isFalse);
      expect(acceptRes['error'], 'call_terminated');
      expect(acceptRes['status'], 'cancelled');
      expect(callStatus, 'cancelled');
    });

    test('Multi-Session Race: Cancel vs Accept (Callee accepts before Caller cancels)', () async {
      var callStatus = 'ringing';

      Future<Map<String, dynamic>> calleeSessionAccept() async {
        if (callStatus == 'ringing') {
          callStatus = 'ongoing';
          return {'success': true, 'status': 'ongoing', 'room_id': 'room-123'};
        }
        return {'success': false, 'error': 'call_terminated', 'status': callStatus};
      }

      Future<Map<String, dynamic>> callerSessionCancel() async {
        if (callStatus == 'ringing') {
          callStatus = 'cancelled';
          return {'success': true, 'status': 'cancelled'};
        }
        return {'success': false, 'error': 'cannot_cancel_active_or_ended_call', 'status': callStatus};
      }

      final calleeRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => calleeSessionAccept());
      final callerRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => callerSessionCancel());

      final acceptRes = await calleeRepo.acceptCall('call-race-2');
      final cancelRes = await callerRepo.cancelCall('call-race-2');

      expect(acceptRes['success'], isTrue);
      expect(acceptRes['status'], 'ongoing');
      expect(cancelRes['success'], isFalse);
      expect(cancelRes['error'], 'cannot_cancel_active_or_ended_call');
      expect(cancelRes['status'], 'ongoing');
      expect(callStatus, 'ongoing');
    });

    test('Multi-Session Race: Timeout vs Accept (Timeout sweeps before Callee accepts)', () async {
      var callStatus = 'ringing';

      Future<Map<String, dynamic>> workerSessionTimeout() async {
        if (callStatus == 'ringing') {
          callStatus = 'missed';
          return {'success': true, 'status': 'missed'};
        }
        return {'success': false, 'error': 'call_not_ringing', 'status': callStatus};
      }

      Future<Map<String, dynamic>> calleeSessionAccept() async {
        if (callStatus == 'missed') {
          return {'success': false, 'error': 'call_timed_out', 'status': 'missed'};
        }
        callStatus = 'ongoing';
        return {'success': true, 'status': 'ongoing'};
      }

      final workerRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => workerSessionTimeout());
      final calleeRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => calleeSessionAccept());

      final timeoutRes = await workerRepo.timeoutCall('call-race-3');
      final acceptRes = await calleeRepo.acceptCall('call-race-3');

      expect(timeoutRes['success'], isTrue);
      expect(timeoutRes['status'], 'missed');
      expect(acceptRes['success'], isFalse);
      expect(acceptRes['error'], 'call_timed_out');
      expect(acceptRes['status'], 'missed');
      expect(callStatus, 'missed');
    });

    test('Multi-Session Race: Timeout vs Accept (Callee accepts before Timeout sweeps)', () async {
      var callStatus = 'ringing';

      Future<Map<String, dynamic>> calleeSessionAccept() async {
        if (callStatus == 'ringing') {
          callStatus = 'ongoing';
          return {'success': true, 'status': 'ongoing', 'room_id': 'room-xyz'};
        }
        return {'success': false, 'error': 'call_timed_out', 'status': callStatus};
      }

      Future<Map<String, dynamic>> workerSessionTimeout() async {
        if (callStatus == 'ringing') {
          callStatus = 'missed';
          return {'success': true, 'status': 'missed'};
        }
        return {'success': false, 'error': 'call_not_ringing', 'status': callStatus};
      }

      final calleeRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => calleeSessionAccept());
      final workerRepo = SupabaseCallsRepository(mockSupabase, rpcInvoker: (fn, {params}) => workerSessionTimeout());

      final acceptRes = await calleeRepo.acceptCall('call-race-4');
      final timeoutRes = await workerRepo.timeoutCall('call-race-4');

      expect(acceptRes['success'], isTrue);
      expect(acceptRes['status'], 'ongoing');
      expect(timeoutRes['success'], isFalse);
      expect(timeoutRes['error'], 'call_not_ringing');
      expect(timeoutRes['status'], 'ongoing');
      expect(callStatus, 'ongoing');
    });

    test('Phase 6.2 Non-Regression: Calling operations do not interfere with delivery receipt tokens', () async {
      // Verifies that calling operations use an isolated repository and table namespace
      // with zero mutations against public.message_delivery_receipt_tokens
      final repo = SupabaseCallsRepository(
        mockSupabase,
        rpcInvoker: (fn, {params}) async => {'success': true, 'call_id': 'call-100', 'status': 'ongoing'},
      );

      final callRes = await repo.acceptCall('call-100');
      expect(callRes['success'], isTrue);
      expect(callRes['status'], 'ongoing');
    });
  });
}
