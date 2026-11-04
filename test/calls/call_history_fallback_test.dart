// ignore_for_file: must_be_immutable, unused_import

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/data/repositories/supabase_calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
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

class _MockSupabaseClient implements SupabaseClient {
  final _FakeGoTrueClient _auth = _FakeGoTrueClient();
  bool primaryQueryShouldFail = false;
  bool fallbackQueryShouldFail = false;
  int callParticipantsQueryCount = 0;
  int profilesQueryCount = 0;

  List<Map<String, dynamic>> mockCallsTable = [];
  List<Map<String, dynamic>> mockParticipantsTable = [];
  List<Map<String, dynamic>> mockProfilesTable = [];

  _MockSupabaseClient() {
    _auth.setCurrentSession(
      _FakeAuthSession(),
      const User(
        id: 'user-auth-1234',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
  }

  @override
  GoTrueClient get auth => _auth;

  @override
  SupabaseQueryBuilder from(String table) {
    return _MockSupabaseQueryBuilder(this, table);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSupabaseQueryBuilder implements SupabaseQueryBuilder {
  final _MockSupabaseClient _client;
  final String _table;

  _MockSupabaseQueryBuilder(this._client, this._table);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _MockPostgrestFilterBuilder(_client, _table, columns);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>>,
               PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  final _MockSupabaseClient _client;
  final String _table;
  final String _columns;

  bool _isEmbedding = false;
  List<dynamic>? _inFilterValues;
  int _offset = 0;
  int _limit = 50;

  _MockPostgrestFilterBuilder(this._client, this._table, this._columns) {
    _isEmbedding = _columns.contains('caller:profiles') || _columns.contains('call_participants(');
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(String column, List<dynamic> values) {
    _inFilterValues = values;
    if (_table == 'call_participants') {
      _client.callParticipantsQueryCount++;
    } else if (_table == 'profiles') {
      _client.profilesQueryCount++;
    }
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(String column, {bool ascending = false, bool nullsFirst = false, String? referencedTable}) {
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> range(int from, int to, {String? referencedTable}) {
    _offset = from;
    _limit = (to - from) + 1;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) {
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) {
    return _execute().then(onValue, onError: onError);
  }

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return _execute().catchError(onError, test: test);
  }

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) {
    return _execute().whenComplete(action);
  }

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) {
    return _execute().timeout(timeLimit, onTimeout: onTimeout);
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    if (_isEmbedding && _client.primaryQueryShouldFail) {
      throw const PostgrestException(
        message: 'Could not find a relationship between calls and profiles in schema cache',
        code: 'PGRST200',
      );
    }

    if (!_isEmbedding && _client.fallbackQueryShouldFail) {
      throw const PostgrestException(
        message: 'Connection refused / network failure',
        code: '500',
      );
    }

    if (_table == 'calls') {
      if (_isEmbedding) {
        // Return enriched with primary embed format
        return _client.mockCallsTable.skip(_offset).take(_limit).toList();
      } else {
        // Return flat calls table
        return _client.mockCallsTable.map((c) {
          final copy = Map<String, dynamic>.from(c);
          copy.remove('caller');
          copy.remove('call_participants');
          return copy;
        }).skip(_offset).take(_limit).toList();
      }
    }

    if (_table == 'call_participants') {
      if (_inFilterValues != null) {
        final ids = _inFilterValues!.map((v) => v.toString()).toSet();
        return _client.mockParticipantsTable
            .where((p) => ids.contains(p['call_id']?.toString()))
            .toList();
      }
      return _client.mockParticipantsTable;
    }

    if (_table == 'profiles') {
      if (_inFilterValues != null) {
        final ids = _inFilterValues!.map((v) => v.toString()).toSet();
        return _client.mockProfilesTable
            .where((pr) => ids.contains(pr['id']?.toString()))
            .toList();
      }
      return _client.mockProfilesTable;
    }

    return const [];
  }
}

void main() {
  group('SupabaseCallsRepository Call History Fallback Tests', () {
    late _MockSupabaseClient client;
    late SupabaseCallsRepository repo;

    setUp(() {
      client = _MockSupabaseClient();
      repo = SupabaseCallsRepository(client);

      // Seed mock database
      client.mockCallsTable = [
        {
          'id': 'call-101',
          'chat_id': 'chat-1',
          'caller_id': 'user-auth-1234',
          'call_type': 'video',
          'is_group': false,
          'status': 'ended',
          'room_id': 'room-101',
          'started_at': '2026-11-01T12:00:00Z',
          'duration_seconds': 120,
          'caller': {
            'id': 'user-auth-1234',
            'display_name': 'Me',
            'avatar_url': 'https://example.com/me.png',
            'phone_e164': '+15550001111',
          },
          'call_participants': [
            {
              'user_id': 'user-peer-5678',
              'status': 'accepted',
              'profile': {
                'id': 'user-peer-5678',
                'display_name': 'Bob Smith',
                'avatar_url': 'https://example.com/bob.png',
                'phone_e164': '+15550002222',
              },
            },
          ],
        },
        {
          'id': 'call-102',
          'chat_id': 'chat-2',
          'caller_id': 'user-peer-5678',
          'call_type': 'audio',
          'is_group': false,
          'status': 'missed',
          'room_id': 'room-102',
          'started_at': '2026-11-01T11:00:00Z',
          'duration_seconds': 0,
          'caller': {
            'id': 'user-peer-5678',
            'display_name': 'Bob Smith',
            'avatar_url': 'https://example.com/bob.png',
            'phone_e164': '+15550002222',
          },
          'call_participants': [
            {
              'user_id': 'user-auth-1234',
              'status': 'missed',
              'profile': {
                'id': 'user-auth-1234',
                'display_name': 'Me',
                'avatar_url': 'https://example.com/me.png',
                'phone_e164': '+15550001111',
              },
            },
          ],
        },
      ];

      client.mockParticipantsTable = [
        {
          'call_id': 'call-101',
          'user_id': 'user-peer-5678',
          'status': 'accepted',
        },
        {
          'call_id': 'call-102',
          'user_id': 'user-auth-1234',
          'status': 'missed',
        },
      ];

      client.mockProfilesTable = [
        {
          'id': 'user-auth-1234',
          'display_name': 'Me',
          'avatar_url': 'https://example.com/me.png',
          'phone_e164': '+15550001111',
        },
        {
          'id': 'user-peer-5678',
          'display_name': 'Bob Smith',
          'avatar_url': 'https://example.com/bob.png',
          'phone_e164': '+15550002222',
        },
      ];
    });

    test('1. Primary relationship embed query succeeds and returns mapped call records', () async {
      client.primaryQueryShouldFail = false;

      final history = await repo.fetchCallHistory();

      expect(history.length, 2);
      expect(history[0].id, 'call-101');
      expect(history[0].callType, CallType.video);
      expect(history[0].peerName, 'Bob Smith');
      expect(history[0].peerAvatarUrl, 'https://example.com/bob.png');
      expect(history[0].isOutgoing('user-auth-1234'), isTrue);

      expect(history[1].id, 'call-102');
      expect(history[1].callType, CallType.audio);
      expect(history[1].peerName, 'Bob Smith');
      expect(history[1].isOutgoing('user-auth-1234'), isFalse);
      expect(history[1].status, CallStatus.missed);
    });

    test('2. Fallback engages when embedding fails and enriches profiles via batched queries', () async {
      client.primaryQueryShouldFail = true;

      final history = await repo.fetchCallHistory();

      expect(history.length, 2);
      // Verify complete caller and peer resolution via batched fallback
      expect(history[0].id, 'call-101');
      expect(history[0].peerName, 'Bob Smith');
      expect(history[0].peerAvatarUrl, 'https://example.com/bob.png');
      expect(history[0].peerPhone, '+15550002222');
      expect(history[0].isOutgoing('user-auth-1234'), isTrue);

      expect(history[1].id, 'call-102');
      expect(history[1].peerName, 'Bob Smith');
      expect(history[1].peerAvatarUrl, 'https://example.com/bob.png');
      expect(history[1].isOutgoing('user-auth-1234'), isFalse);

      // Verify batched queries were used (exactly 1 for participants, 1 for profiles, no N+1)
      expect(client.callParticipantsQueryCount, 1);
      expect(client.profilesQueryCount, 1);
    });

    test('3. Missing profiles in fallback are handled safely without fabricating dummy data', () async {
      client.primaryQueryShouldFail = true;
      // Empty the profiles table
      client.mockProfilesTable.clear();

      final history = await repo.fetchCallHistory();

      expect(history.length, 2);
      expect(history[0].id, 'call-101');
      // Gracefully handles missing profile without throwing or crashing
      expect(history[0].peerName, isNull);
      expect(history[0].peerAvatarUrl, isNull);
    });

    test('4. Actual database query failures are NOT disguised as empty results', () async {
      client.primaryQueryShouldFail = true;
      client.fallbackQueryShouldFail = true;

      expect(
        () => repo.fetchCallHistory(),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
