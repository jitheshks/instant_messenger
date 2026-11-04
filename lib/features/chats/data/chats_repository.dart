import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/sync/chat_preview_ordering_policy.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/domain/services/chat_latest_activity_resolver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatsRepository {
  final SupabaseClient? _supabaseClient;
  ChatsStore? _chatsStore;
  RealtimeConnectionManager? _connectionManager;
  final StreamController<RealtimeSubscribeStatus> _realtimeStatusController =
      StreamController<RealtimeSubscribeStatus>.broadcast();

  ChatsRepository({
    SupabaseClient? supabaseClient,
    ChatsStore? chatsStore,
    RealtimeConnectionManager? connectionManager,
  })  : _supabaseClient = supabaseClient,
        _chatsStore = chatsStore,
        _connectionManager = connectionManager;

  /// Attaches or updates the account-scoped [ChatsStore] instance.
  void attachChatsStore(ChatsStore store) {
    _chatsStore = store;
  }

  /// Attaches or updates the active [RealtimeConnectionManager].
  void attachConnectionManager(RealtimeConnectionManager connectionManager) {
    _connectionManager = connectionManager;
  }

  /// Exposes the active connection manager if attached.
  RealtimeConnectionManager? get connectionManager => _connectionManager;

  /// Exposes high-level Realtime connection status stream.
  Stream<RealtimeConnectionStatus>? get onRealtimeConnectionStatus =>
      _connectionManager?.onStatusChanged;

  /// Exposes direct reactive stream of locally persisted conversation summaries.
  Stream<List<ChatSummary>>? watchLocalChats() =>
      _chatsStore?.watchChatSummaries();

  /// Stream emitting Realtime channel status transitions.
  Stream<RealtimeSubscribeStatus> get onRealtimeStatusChanged =>
      _realtimeStatusController.stream;

  SupabaseClient get _sb => _supabaseClient ?? Supabase.instance.client;

  /// Returns a stream of chat summaries for the authenticated user.
  ///
  /// Listens to Supabase PostgREST for chat summaries and subscribes to Realtime
  /// postgres changes on `chats` and `chat_members` to auto-refresh the list.
  /// Fetches chat summaries once for the specified user or current user from Supabase.
  Future<List<ChatSummary>> fetchUserChats([String? currentUserId]) async {
    final uid = (currentUserId != null && currentUserId.isNotEmpty)
        ? currentUserId
        : _sb.auth.currentUser?.id;

    if (uid == null || uid.isEmpty) {
      debugPrint('[ChatsRepo] No authenticated Supabase user');
      return const <ChatSummary>[];
    }

    final rows = await _sb
        .from('chats')
        .select('''
          id,
          type,
          title,
          avatar_url,
          last_message,
          last_message_time,
          last_sender_id,
          last_message_status,
          updated_at,
          chat_members(
            user_id,
            role,
            unread_count,
            muted,
            profile:profiles(
              id,
              display_name,
              avatar_url,
              phone_e164
            )
          )
        ''')
        .order('updated_at', ascending: false);

    final summaries = (rows as List)
        .map(
          (r) => ChatSummary.fromSupabase(r as Map<String, dynamic>, uid),
        )
        .toList();

    // Batched retrieval of latest call events for retrieved conversations (avoids N+1)
    final chatIds = summaries
        .map((s) => s.id)
        .where((id) => id.isNotEmpty)
        .toList();

    final latestCallByChatId = <String, CallRecord>{};
    if (chatIds.isNotEmpty) {
      try {
        final callRows = await _sb
            .from('calls')
            .select('''
              id,
              chat_id,
              caller_id,
              call_type,
              status,
              started_at,
              ended_at,
              duration_seconds,
              is_group,
              call_participants(user_id, status)
            ''')
            .inFilter('chat_id', chatIds)
            .order('started_at', ascending: false)
            .limit(100);

        for (final r in (callRows as List)) {
          if (r is Map) {
            final cMap = Map<String, dynamic>.from(r);
            final cId = cMap['chat_id']?.toString() ?? '';
            if (cId.isNotEmpty && !latestCallByChatId.containsKey(cId)) {
              latestCallByChatId[cId] = CallRecord.fromSupabase(cMap, uid);
            }
          }
        }
      } catch (callErr) {
        debugPrint('[ChatsRepo] Non-fatal latest call fetch notice: $callErr');
      }
    }

    // Resolve latest activity per conversation across messages and call events
    final activityResolvedSummaries = summaries.map((s) {
      final latestCall = latestCallByChatId[s.id];
      if (latestCall != null) {
        final activity = ChatLatestActivityResolver.resolveLatestActivity(
          messageTime: s.lastTime,
          messagePreview: s.lastMessage,
          lastSenderId: s.lastSenderId,
          lastMessageStatus: s.lastMessageStatus,
          lastMessageId: s.lastMessageId,
          latestCall: latestCall,
          currentUserId: uid,
        );
        if (activity.isCallActivity) {
          return s.copyWith(
            lastMessage: activity.previewText,
            lastTime: activity.timestamp,
            lastSenderId: activity.senderId,
            lastMessageStatus: activity.status,
            lastMessageId: activity.activityId,
          );
        }
      }
      return s;
    }).toList();

    // Merge with local ChatsStore summaries to protect newer optimistic previews
    final mergedSummaries = <ChatSummary>[];
    for (final remote in activityResolvedSummaries) {
      final local = _chatsStore?.getChatSummary(remote.id);
      if (local != null) {
        final action = ChatPreviewOrderingPolicy.evaluate(
          candidateTime: remote.lastTime,
          candidateMessageId: remote.lastMessageId,
          existingTime: local.lastTime,
          existingMessageId: local.lastMessageId,
        );

        // If local is strictly newer, or if timestamps are equal and local has a pending/established preview,
        // preserve the local preview, timestamp, sender, status, and message ID.
        if (action == CandidateAction.ignoreCandidate ||
            (remote.lastTime.isAtSameMomentAs(local.lastTime) &&
                local.lastMessageStatus == 0)) {
          mergedSummaries.add(
            remote.copyWith(
              lastMessage: local.lastMessage,
              lastTime: local.lastTime,
              lastSenderId: local.lastSenderId,
              lastMessageStatus: local.lastMessageStatus,
              lastMessageId: local.lastMessageId,
            ),
          );
          continue;
        }

        // If remote is adopted (e.g. newer), but remote has no lastMessageId,
        // check if local message ID can be preserved when messages or times match
        if (remote.lastMessageId == null && local.lastMessageId != null) {
          if (remote.lastMessage == local.lastMessage ||
              remote.lastTime.isAtSameMomentAs(local.lastTime)) {
            mergedSummaries.add(
              remote.copyWith(lastMessageId: local.lastMessageId),
            );
            continue;
          }
        }
      }
      mergedSummaries.add(remote);
    }

    // Sort conversations chronologically by latest activity
    mergedSummaries.sort((a, b) => b.lastTime.compareTo(a.lastTime));

    // Write-through to Hive ChatsStore if available
    if (_chatsStore != null) {
      try {
        await _chatsStore!.saveChatSummaries(mergedSummaries);
      } catch (e) {
        debugPrint('[ChatsRepo] Non-fatal cache write-through notice: $e');
      }
    }

    return mergedSummaries;
  }

  /// Returns a stream of chat summaries for the authenticated user.
  ///
  /// Listens to Supabase PostgREST for chat summaries and subscribes to Realtime
  /// postgres changes on `chats` and `chat_members` to auto-refresh the list.
  Stream<List<ChatSummary>> watchUserChats([String? currentUserId]) {
    final uid = (currentUserId != null && currentUserId.isNotEmpty)
        ? currentUserId
        : _sb.auth.currentUser?.id;

    if (uid == null || uid.isEmpty) {
      debugPrint('[ChatsRepo] No authenticated Supabase user');
      return Stream.value(const <ChatSummary>[]);
    }

    late final StreamController<List<ChatSummary>> controller;
    RealtimeChannel? channel;
    int fetchGeneration = 0;
    bool hasEmittedSuccess = false;

    Future<void> fetchAndEmit() async {
      final currentGen = ++fetchGeneration;
      try {
        final summaries = await fetchUserChats(uid);

        // Guard against stale out-of-order responses from concurrent fetches
        if (currentGen < fetchGeneration) {
          return;
        }

        hasEmittedSuccess = true;
        if (!controller.isClosed) {
          controller.add(summaries);
        }
      } catch (e, st) {
        if (currentGen == fetchGeneration && !controller.isClosed) {
          debugPrint('[ChatsRepo] Supabase fetch chats error: $e');
          controller.addError(e, st);
        }
      }
    }

    StreamSubscription<AuthState>? authSub;
    Timer? reconnectTimer;

    void startSubscription() {
      // 0. Emit local cached data immediately for instant offline rendering
      if (_chatsStore != null) {
        try {
          final cached = _chatsStore!.getAllChatSummaries();
          if (cached.isNotEmpty && !controller.isClosed) {
            controller.add(cached);
          }
        } catch (e) {
          debugPrint('[ChatsRepo] Non-fatal local cache read notice: $e');
        }
      }

      late void Function() scheduleReconnect;
      late void Function() setupChannel;

      setupChannel = () {
        if (controller.isClosed) return;
        final channelTopic = 'user_chats:$uid';
        if (channel != null) {
          try {
            _sb.removeChannel(channel!);
          } catch (_) {
            channel?.unsubscribe();
          }
          channel = null;
        }

        _connectionManager?.registerRequiredChannel(channelTopic);
        channel = _sb.channel(channelTopic);
        channel!
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chats',
              callback: (_) => fetchAndEmit(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'chat_members',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              callback: (_) => fetchAndEmit(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'calls',
              callback: (_) => fetchAndEmit(),
            )
            .subscribe((status, [error]) {
              if (!_realtimeStatusController.isClosed) {
                _realtimeStatusController.add(status);
              }
              _connectionManager?.reportChannelStatus(channelTopic, status, error);
              if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                debugPrint(
                  '[ChatsRepo] Realtime subscription status: $status, error: $error',
                );
                if (_connectionManager == null) {
                  scheduleReconnect();
                }
                if (!controller.isClosed && error != null && !hasEmittedSuccess) {
                  controller.addError(error);
                }
              } else if (status == RealtimeSubscribeStatus.subscribed) {
                reconnectTimer?.cancel();
                fetchAndEmit();
              }
            });
      };

      scheduleReconnect = () {
        if (controller.isClosed) return;
        reconnectTimer?.cancel();
        reconnectTimer = Timer(const Duration(seconds: 4), () {
          if (!controller.isClosed) {
            setupChannel();
            fetchAndEmit();
          }
        });
      };

      // 1. Initial load when first listener attaches
      fetchAndEmit();

      // 2. Set up realtime channel subscription
      setupChannel();

      // 3. Listen for token refresh to resubscribe channel
      try {
        authSub = _sb.auth.onAuthStateChange.listen((data) {
          if (controller.isClosed) return;
          final event = data.event;
          if (event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.signedIn) {
            debugPrint('[ChatsRepo] Token refreshed ($event) -> reconnecting Realtime');
            setupChannel();
            fetchAndEmit();
          }
        });
      } catch (_) {}
    }

    void stopSubscription() {
      reconnectTimer?.cancel();
      reconnectTimer = null;
      authSub?.cancel();
      authSub = null;
      _connectionManager?.unregisterChannel('user_chats:$uid');
      if (channel != null) {
        try {
          _sb.removeChannel(channel!);
        } catch (_) {
          channel?.unsubscribe();
        }
        channel = null;
      }
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<List<ChatSummary>>.broadcast(
      onListen: startSubscription,
      onCancel: stopSubscription,
    );

    return controller.stream;
  }

  /// Leaves a chat conversation via Supabase RPC `leave_chat`.
  Future<void> leaveChat(String chatId) async {
    await _sb.rpc('leave_chat', params: {'p_chat_id': chatId});
  }

  /// Fetches group conversations for the authenticated user.
  Future<List<ChatSummary>> fetchUserGroups([String? currentUserId]) async {
    final chats = await fetchUserChats(currentUserId);
    return chats.where((c) => c.isGroup).toList();
  }

  /// Returns a stream of group conversations for the authenticated user.
  Stream<List<ChatSummary>> watchUserGroups([String? currentUserId]) {
    return watchUserChats(currentUserId).map(
      (chats) => chats.where((c) => c.isGroup).toList(),
    );
  }
}
