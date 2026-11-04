// lib/features/calls/data/repositories/supabase_calls_repository.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/sync/realtime_connection_manager.dart';
import '../../domain/models/call_enums.dart';
import '../../domain/models/call_record.dart';
import '../../domain/models/zego_token_response.dart';
import '../../domain/repositories/calls_repository.dart';

/// Function signature for invoking Supabase Edge Functions.
/// Used to enable isolated unit test mocking without live network calls.
typedef EdgeFunctionInvoker =
    Future<FunctionResponse> Function(
      String functionName, {
      Map<String, String>? headers,
      Object? body,
    });

/// Function signature for invoking Supabase RPCs.
/// Used to enable isolated unit test mocking without live database connection.
typedef RpcInvoker =
    Future<dynamic> Function(
      String fnName, {
      Map<String, dynamic>? params,
    });

/// Supabase implementation of [CallsRepository].
///
/// Securely requests ZEGOCLOUD Token04 from the `get-zego-token` Edge Function
/// using the caller's active Supabase Auth JWT, and executes atomic calling RPCs.
class SupabaseCallsRepository implements CallsRepository {
  final SupabaseClient _supabase;
  final EdgeFunctionInvoker? _functionInvoker;
  final RpcInvoker? _rpcInvoker;
  RealtimeConnectionManager? _connectionManager;

  SupabaseCallsRepository(
    this._supabase, {
    RealtimeConnectionManager? connectionManager,
    EdgeFunctionInvoker? functionInvoker,
    RpcInvoker? rpcInvoker,
  })  : _connectionManager = connectionManager,
        _functionInvoker = functionInvoker,
        _rpcInvoker = rpcInvoker;

  @override
  void attachConnectionManager(dynamic connectionManager) {
    if (connectionManager is RealtimeConnectionManager) {
      _connectionManager = connectionManager;
    }
  }

  /// Exposes the active connection manager if attached.
  RealtimeConnectionManager? get connectionManager => _connectionManager;

  @override
  Future<ZegoTokenResponse> getZegoToken({
    String? callId,
    String? roomId,
    int? effectiveTimeInSeconds,
    CallType? callType,
  }) async {
    // 1. Enforce active authentication
    final session = _supabase.auth.currentSession;
    final currentUserId = _supabase.auth.currentUser?.id;

    if (session == null || currentUserId == null || currentUserId.isEmpty) {
      throw const CallsException(
        'User is not authenticated. A valid Supabase session is required to request calling tokens.',
        statusCode: 401,
      );
    }

    // 2. Build sanitized request payload
    final payload = <String, dynamic>{};
    if (callId != null && callId.trim().isNotEmpty) {
      payload['call_id'] = callId.trim();
    }
    if (roomId != null && roomId.trim().isNotEmpty) {
      payload['room_id'] = roomId.trim();
    }
    if (effectiveTimeInSeconds != null && effectiveTimeInSeconds > 0) {
      payload['effective_time_in_seconds'] = effectiveTimeInSeconds;
    }
    if (callType != null) {
      payload['call_type'] = callType.toJson();
    }

    // 3. Dispatch to `get-zego-token` Edge Function
    try {
      final response = _functionInvoker != null
          ? await _functionInvoker('get-zego-token', body: payload)
          : await _supabase.functions.invoke('get-zego-token', body: payload);

      final status = response.status;
      final rawData = response.data;

      if (status < 200 || status >= 300) {
        String errorMessage = 'Edge Function returned error status: $status';
        if (rawData is Map && rawData['error'] is String) {
          errorMessage = rawData['error'] as String;
        } else if (rawData is String) {
          try {
            final parsed = jsonDecode(rawData);
            if (parsed is Map && parsed['error'] is String) {
              errorMessage = parsed['error'] as String;
            }
          } catch (_) {}
        }
        throw CallsException(errorMessage, statusCode: status);
      }

      // 4. Parse response data safely
      Map<String, dynamic> jsonMap;
      if (rawData is Map) {
        jsonMap = Map<String, dynamic>.from(rawData);
      } else if (rawData is String) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map) {
            jsonMap = Map<String, dynamic>.from(decoded);
          } else {
            throw const FormatException(
              'Expected JSON map from get-zego-token',
            );
          }
        } catch (e) {
          throw CallsException(
            'Failed to parse get-zego-token JSON response: $e',
            cause: e,
          );
        }
      } else {
        throw const CallsException(
          'Malformed response data received from get-zego-token',
        );
      }

      final tokenResponse = ZegoTokenResponse.fromJson(jsonMap);

      if (kDebugMode) {
        debugPrint(
          '[SupabaseCallsRepository] Successfully acquired ZegoToken '
          '(appId: ${tokenResponse.appId}, user: ${tokenResponse.userId}, '
          'expiresIn: ${tokenResponse.remainingSeconds}s)',
        );
      }

      return tokenResponse;
    } on CallsException {
      rethrow;
    } on FunctionException catch (fe) {
      String msg = 'FunctionException (status: ${fe.status})';
      if (fe.details is Map && (fe.details as Map)['error'] is String) {
        msg = (fe.details as Map)['error'] as String;
      } else if (fe.details != null) {
        msg = fe.details.toString();
      }
      throw CallsException(msg, statusCode: fe.status, cause: fe);
    } catch (e) {
      throw CallsException(
        'Unexpected failure requesting ZEGOCLOUD token: $e',
        cause: e,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeRpc(
    String fnName,
    Map<String, dynamic> params,
  ) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw const CallsException(
        'User is not authenticated. A valid Supabase session is required.',
        statusCode: 401,
      );
    }

    try {
      final dynamic raw = _rpcInvoker != null
          ? await _rpcInvoker(fnName, params: params)
          : await _supabase.rpc(fnName, params: params);

      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return {'success': true, 'data': raw};
    } on PostgrestException catch (pe) {
      throw CallsException(
        pe.message,
        statusCode: int.tryParse(pe.code ?? '') ?? 500,
        cause: pe,
      );
    } catch (e) {
      if (e is CallsException) rethrow;
      throw CallsException('Failed to execute $fnName: $e', cause: e);
    }
  }

  @override
  Future<Map<String, dynamic>> initiateCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
  }) {
    return _invokeRpc('initiate_call', {
      'p_chat_id': chatId,
      'p_call_type': callType.toJson(),
      'p_invitee_ids': inviteeIds,
    });
  }

  @override
  Future<Map<String, dynamic>> acceptCall(String callId) {
    return _invokeRpc('accept_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> rejectCall(String callId) {
    return _invokeRpc('reject_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> cancelCall(String callId) {
    return _invokeRpc('cancel_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> leaveCall(String callId) {
    return _invokeRpc('leave_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> inviteToCall({
    required String callId,
    required List<String> inviteeIds,
  }) {
    return _invokeRpc('invite_to_call', {
      'p_call_id': callId,
      'p_invitee_ids': inviteeIds,
    });
  }

  @override
  Future<Map<String, dynamic>> rejoinCall(String callId) {
    return _invokeRpc('rejoin_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) {
    return _invokeRpc('heartbeat_call', {'p_call_id': callId});
  }

  @override
  Future<Map<String, dynamic>> timeoutCall(String callId) {
    return _invokeRpc('timeout_call', {'p_call_id': callId});
  }

  @override
  Future<List<CallRecord>> fetchCallHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return const [];
    }

    try {
      final rows = await _supabase
          .from('calls')
          .select('''
            id,
            chat_id,
            caller_id,
            call_type,
            is_group,
            status,
            room_id,
            started_at,
            connected_at,
            ended_at,
            duration_seconds,
            created_at,
            updated_at,
            caller:profiles!calls_caller_id_fkey(
              id,
              display_name,
              avatar_url,
              phone_e164
            ),
            call_participants(
              user_id,
              status,
              profile:profiles(
                id,
                display_name,
                avatar_url,
                phone_e164
              )
            )
          ''')
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return rows
          .map((r) => CallRecord.fromSupabase(Map<String, dynamic>.from(r as Map), uid))
          .toList();
    } catch (e) {
      debugPrint('[SupabaseCallsRepository] Primary relationship embed failed ($e); using batched fallback.');
      final fallbackRows = await _supabase
          .from('calls')
          .select('*')
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return _enrichCallsWithBatchedProfiles(fallbackRows, uid);
    }
  }

  /// Batched resolution fallback when PostgREST relationship embeds fail.
  ///
  /// Reconstructs complete participant profiles and caller information using
  /// exactly two batched `.inFilter()` queries without N+1 overhead.
  Future<List<CallRecord>> _enrichCallsWithBatchedProfiles(
    List<dynamic> callRows,
    String? currentUid,
  ) async {
    if (callRows.isEmpty) return const [];

    final rawCallMaps = callRows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final callIds = <String>{};
    final userIds = <String>{};

    for (final c in rawCallMaps) {
      final cid = c['id']?.toString();
      if (cid != null && cid.isNotEmpty) {
        callIds.add(cid);
      }
      final callerId = c['caller_id']?.toString();
      if (callerId != null && callerId.isNotEmpty) {
        userIds.add(callerId);
      }
    }

    // Batched query 1: fetch participants for all retrieved calls
    final participantsByCallId = <String, List<Map<String, dynamic>>>{};
    if (callIds.isNotEmpty) {
      try {
        final participantRows = await _supabase
            .from('call_participants')
            .select('call_id, user_id, status')
            .inFilter('call_id', callIds.toList());

        for (final p in (participantRows as List)) {
          if (p is Map) {
            final pMap = Map<String, dynamic>.from(p);
            final cId = pMap['call_id']?.toString();
            final pUid = pMap['user_id']?.toString();
            if (pUid != null && pUid.isNotEmpty) {
              userIds.add(pUid);
            }
            if (cId != null && cId.isNotEmpty) {
              participantsByCallId.putIfAbsent(cId, () => []).add(pMap);
            }
          }
        }
      } catch (pErr) {
        debugPrint('[SupabaseCallsRepository] Fallback participant fetch note: $pErr');
      }
    }

    // Batched query 2: fetch profiles for all callers and participants
    final profileMap = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      try {
        final profileRows = await _supabase
            .from('profiles')
            .select('id, display_name, avatar_url, phone_e164')
            .inFilter('id', userIds.toList());

        for (final pr in (profileRows as List)) {
          if (pr is Map) {
            final id = pr['id']?.toString();
            if (id != null && id.isNotEmpty) {
              profileMap[id] = Map<String, dynamic>.from(pr);
            }
          }
        }
      } catch (profErr) {
        debugPrint('[SupabaseCallsRepository] Fallback profile fetch note: $profErr');
      }
    }

    // Attach resolved profiles to participants and call records
    for (final participants in participantsByCallId.values) {
      for (final p in participants) {
        final pUid = p['user_id']?.toString();
        if (pUid != null && profileMap.containsKey(pUid)) {
          p['profile'] = profileMap[pUid];
        }
      }
    }

    final enriched = rawCallMaps.map((c) {
      final callerId = c['caller_id']?.toString();
      if (callerId != null && profileMap.containsKey(callerId)) {
        c['caller'] = profileMap[callerId];
      }
      final cId = c['id']?.toString();
      if (cId != null && participantsByCallId.containsKey(cId)) {
        c['call_participants'] = participantsByCallId[cId];
      }
      return CallRecord.fromSupabase(c, currentUid);
    }).toList();

    return enriched;
  }

  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return const [];

    try {
      final rows = await _supabase
          .from('calls')
          .select('''
            id,
            chat_id,
            caller_id,
            call_type,
            is_group,
            status,
            room_id,
            started_at,
            connected_at,
            ended_at,
            duration_seconds,
            created_at,
            updated_at,
            caller:profiles!calls_caller_id_fkey(
              id,
              display_name,
              avatar_url,
              phone_e164
            ),
            call_participants(
              user_id,
              status,
              profile:profiles(
                id,
                display_name,
                avatar_url,
                phone_e164
              )
            )
          ''')
          .inFilter('status', ['ringing', 'ongoing'])
          .order('started_at', ascending: false);

      return (rows as List)
          .map((r) => CallRecord.fromSupabase(Map<String, dynamic>.from(r as Map), uid))
          .toList();
    } catch (e) {
      debugPrint('[SupabaseCallsRepository] Active calls embed failed ($e); using batched fallback.');
      try {
        final fallbackRows = await _supabase
            .from('calls')
            .select('*')
            .inFilter('status', ['ringing', 'ongoing'])
            .order('started_at', ascending: false);

        return await _enrichCallsWithBatchedProfiles(fallbackRows, uid);
      } catch (fErr) {
        debugPrint('[SupabaseCallsRepository] fetchActiveCallsForUser fallback error: $fErr');
        return const [];
      }
    }
  }

  @override
  Future<CallRecord?> getCallById(String callId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return null;
    final cleanId = callId.trim();
    if (cleanId.isEmpty) return null;

    try {
      final row = await _supabase
          .from('calls')
          .select('''
            id,
            chat_id,
            caller_id,
            call_type,
            is_group,
            status,
            room_id,
            started_at,
            connected_at,
            ended_at,
            duration_seconds,
            created_at,
            updated_at,
            caller:profiles!calls_caller_id_fkey(
              id,
              display_name,
              avatar_url,
              phone_e164
            ),
            call_participants(
              id,
              user_id,
              status,
              joined_at,
              left_at,
              profile:profiles!fk_call_participants_profiles(
                id,
                display_name,
                avatar_url,
                phone_e164
              )
            )
          ''')
          .eq('id', cleanId)
          .maybeSingle();

      if (row == null) return null;
      return CallRecord.fromSupabase(row, uid);
    } catch (e) {
      debugPrint('[SupabaseCallsRepository] getCallById error: $e');
      try {
        final fallbackRow = await _supabase
            .from('calls')
            .select('*')
            .eq('id', cleanId)
            .maybeSingle();

        if (fallbackRow == null) return null;
        final enriched = await _enrichCallsWithBatchedProfiles([fallbackRow], uid);
        return enriched.isNotEmpty ? enriched.first : null;
      } catch (fErr) {
        debugPrint('[SupabaseCallsRepository] getCallById fallback error: $fErr');
        return null;
      }
    }
  }

  @override
  Stream<List<CallRecord>> watchCallHistory() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    late final StreamController<List<CallRecord>> controller;
    RealtimeChannel? channel;
    StreamSubscription<RealtimeConnectionStatus>? rcmSub;
    final channelTopic = 'call_history:$uid';
    int fetchGeneration = 0;

    Future<void> fetchAndEmit() async {
      final currentGen = ++fetchGeneration;
      try {
        final history = await fetchCallHistory();
        if (currentGen < fetchGeneration) return;
        if (!controller.isClosed) {
          controller.add(history);
        }
      } catch (e, st) {
        if (currentGen == fetchGeneration && !controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    void setupChannel() {
      if (controller.isClosed) return;

      if (channel != null) {
        try {
          _supabase.removeChannel(channel!);
        } catch (_) {
          channel?.unsubscribe();
        }
        channel = null;
      }

      _connectionManager?.registerRequiredChannel(channelTopic);
      channel = _supabase.channel(channelTopic);
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'calls',
            callback: (_) => fetchAndEmit(),
          )
          .subscribe((status, [error]) {
            _connectionManager?.reportChannelStatus(channelTopic, status, error);
            if (status == RealtimeSubscribeStatus.subscribed) {
              fetchAndEmit();
            }
          });
    }

    void startSubscription() {
      // 1. Initial REST fetch
      fetchAndEmit();

      // 2. Setup Realtime channel
      setupChannel();

      // 3. Listen to RealtimeConnectionManager reconnection recovery
      if (_connectionManager != null) {
        rcmSub = _connectionManager!.onStatusChanged.listen((status) {
          if (status == RealtimeConnectionStatus.connected) {
            fetchAndEmit();
          }
        });
      }
    }

    void stopSubscription() {
      rcmSub?.cancel();
      rcmSub = null;
      _connectionManager?.unregisterChannel(channelTopic);

      if (channel != null) {
        try {
          _supabase.removeChannel(channel!);
        } catch (_) {
          channel?.unsubscribe();
        }
        channel = null;
      }
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<List<CallRecord>>.broadcast(
      onListen: startSubscription,
      onCancel: stopSubscription,
    );

    return controller.stream;
  }

  @override
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (chatId.isEmpty) return const [];

    try {
      final rows = await _supabase
          .from('calls')
          .select('''
            id,
            chat_id,
            caller_id,
            call_type,
            is_group,
            status,
            room_id,
            started_at,
            connected_at,
            ended_at,
            duration_seconds,
            created_at,
            updated_at,
            caller:profiles!calls_caller_id_fkey(
              id,
              display_name,
              avatar_url,
              phone_e164
            ),
            call_participants(
              user_id,
              status,
              profile:profiles(
                id,
                display_name,
                avatar_url,
                phone_e164
              )
            )
          ''')
          .eq('chat_id', chatId)
          .order('started_at', ascending: true);

      return rows
          .map((r) => CallRecord.fromSupabase(Map<String, dynamic>.from(r as Map), uid))
          .toList();
    } catch (e) {
      debugPrint('[SupabaseCallsRepository] Primary relationship embed failed for chat ($e); using batched fallback.');
      final fallbackRows = await _supabase
          .from('calls')
          .select('*')
          .eq('chat_id', chatId)
          .order('started_at', ascending: true);

      return _enrichCallsWithBatchedProfiles(fallbackRows, uid);
    }
  }

  @override
  Stream<List<CallRecord>> watchCallsForChat(String chatId) {
    if (chatId.isEmpty) return Stream.value(const []);

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    late final StreamController<List<CallRecord>> controller;
    RealtimeChannel? channel;
    StreamSubscription<RealtimeConnectionStatus>? rcmSub;
    final channelTopic = 'chat_calls:$chatId';
    int fetchGeneration = 0;

    Future<void> fetchAndEmit() async {
      final currentGen = ++fetchGeneration;
      try {
        final calls = await fetchCallsForChat(chatId);
        if (currentGen < fetchGeneration) return;
        if (!controller.isClosed) {
          controller.add(calls);
        }
      } catch (e, st) {
        if (currentGen == fetchGeneration && !controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    void setupChannel() {
      if (controller.isClosed) return;

      if (channel != null) {
        try {
          _supabase.removeChannel(channel!);
        } catch (_) {
          channel?.unsubscribe();
        }
        channel = null;
      }

      _connectionManager?.registerRequiredChannel(channelTopic);
      channel = _supabase.channel(channelTopic);
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: chatId,
            ),
            callback: (_) => fetchAndEmit(),
          )
          .subscribe((status, [error]) {
            _connectionManager?.reportChannelStatus(channelTopic, status, error);
            if (status == RealtimeSubscribeStatus.subscribed) {
              fetchAndEmit();
            }
          });
    }

    void startSubscription() {
      // 1. Initial REST fetch
      fetchAndEmit();

      // 2. Setup Realtime channel
      setupChannel();

      // 3. Listen to RealtimeConnectionManager reconnection recovery
      if (_connectionManager != null) {
        rcmSub = _connectionManager!.onStatusChanged.listen((status) {
          if (status == RealtimeConnectionStatus.connected) {
            fetchAndEmit();
          }
        });
      }
    }

    void stopSubscription() {
      rcmSub?.cancel();
      rcmSub = null;
      _connectionManager?.unregisterChannel(channelTopic);

      if (channel != null) {
        try {
          _supabase.removeChannel(channel!);
        } catch (_) {
          channel?.unsubscribe();
        }
        channel = null;
      }
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<List<CallRecord>>.broadcast(
      onListen: startSubscription,
      onCancel: stopSubscription,
    );

    return controller.stream;
  }
}
