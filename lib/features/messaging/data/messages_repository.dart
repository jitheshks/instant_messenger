import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_model.dart';
import 'package:instant_messenger/shared/utils/chat_id_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository managing message timelines, optimistic local persistence via [MessagesStore],
/// outbox dispatch via [OutboxDaemon], and remote synchronization with Supabase.
class MessagesRepository {
  final SupabaseClient? _supabaseClient;
  MessagesStore? _messagesStore;
  OutboxDaemon? _outboxDaemon;
  ChatsStore? _chatsStore;
  final _recentDeliveryAcks = <String>{};

  MessagesRepository({
    @Deprecated(
      'Unused parameter. Maintained temporarily until AppBootstrap is cleaned.',
    )
    dynamic db,
    SupabaseClient? supabaseClient,
    MessagesStore? messagesStore,
    OutboxDaemon? outboxDaemon,
    ChatsStore? chatsStore,
  }) : _supabaseClient = supabaseClient,
       _messagesStore = messagesStore,
       _outboxDaemon = outboxDaemon,
       _chatsStore = chatsStore;

  /// Attaches or updates the account-scoped [MessagesStore] instance.
  void attachMessagesStore(MessagesStore store) {
    _messagesStore = store;
  }

  /// Attaches or updates the active [OutboxDaemon].
  void attachOutboxDaemon(OutboxDaemon daemon) {
    _outboxDaemon = daemon;
  }

  /// Attaches or updates the active [ChatsStore].
  void attachChatsStore(ChatsStore store) {
    _chatsStore = store;
  }

  MessagesStore? get messagesStore => _messagesStore;
  OutboxDaemon? get outboxDaemon => _outboxDaemon;
  ChatsStore? get chatsStore => _chatsStore;

  /// Retries an outbox mutation for [messageId] via the active [OutboxDaemon].
  Future<void> retryMessage(String messageId) async {
    final daemon = _outboxDaemon;
    if (daemon != null) {
      await daemon.retryExhausted(messageId);
    }
  }

  /// Exposes direct reactive stream of locally persisted messages for [chatId].
  Stream<List<ChatMessage>>? watchLocalMessages(
    String chatId, {
    int limit = 50,
  }) => _messagesStore?.watchMessages(chatId, limit: limit);

  SupabaseClient get _sb => _supabaseClient ?? Supabase.instance.client;

  SupabaseClient? get _safeSb {
    if (_supabaseClient != null) return _supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static String pairChatId(String a, String b) => ChatIdService.pair(a, b);

  Future<List<ChatMessage>> loadLatestMessages(
    String chatId, {
    int limit = 30,
  }) async {
    final myUid = _sb.auth.currentUser?.id;
    final rows = await _sb
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .order('sent_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((d) => ChatMessage.fromSupabase(d as Map<String, dynamic>, myUid))
        .toList();
  }

  Future<List<ChatMessage>> loadOlderMessages(
    String chatId,
    dynamic lastDocOrSentAt, {
    int limit = 30,
  }) async {
    DateTime? sentAt;
    if (lastDocOrSentAt is DateTime) {
      sentAt = lastDocOrSentAt;
    } else if (lastDocOrSentAt is String) {
      sentAt = DateTime.tryParse(lastDocOrSentAt);
    } else if (lastDocOrSentAt is ChatMessage) {
      sentAt = lastDocOrSentAt.sentAt;
    }
    if (sentAt == null) return const [];

    final myUid = _sb.auth.currentUser?.id;
    final rows = await _sb
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .lt('sent_at', sentAt.toUtc().toIso8601String())
        .order('sent_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((d) => ChatMessage.fromSupabase(d as Map<String, dynamic>, myUid))
        .toList();
  }

  // ---------------- CHAT DOC ----------------

  /// Resolves or initializes a direct chat with [peerId] via Supabase RPC,
  /// returning the canonical PostgreSQL UUID for the conversation.
  Future<String?> getOrCreateDirectChat(String peerId) async {
    final sb = _safeSb;
    if (sb == null) return null;

    try {
      final res = await sb.rpc(
        'get_or_create_direct_chat',
        params: {'p_peer_id': peerId},
      );
      if (res is String && res.isNotEmpty) {
        return res;
      }
      return res?.toString();
    } catch (e) {
      debugPrint('[MessagesRepo] getOrCreateDirectChat error: $e');
      rethrow;
    }
  }

  Future<void> ensureChatDoc({
    required String chatId,
    required String uidA,
    required String uidB,
    required String title,
    String? avatarUrl,
  }) async {
    final sb = _safeSb;
    if (sb == null) return;

    final myUid = sb.auth.currentUser?.id ?? uidA;
    final otherUid = uidA == myUid ? uidB : uidA;

    try {
      await sb.rpc(
        'get_or_create_direct_chat',
        params: {'p_peer_id': otherUid},
      );
    } catch (e) {
      debugPrint('[MessagesRepo] get_or_create_direct_chat notice: $e');
    }
  }

  // ---------------- STREAM ----------------

  Stream<List<ChatMessage>> watchChat(String chatId) {
    late final StreamController<List<ChatMessage>> controller;
    RealtimeChannel? channel;
    int fetchGeneration = 0;

    Future<void> fetchAndEmit() async {
      final currentGen = ++fetchGeneration;
      try {
        final myUid = _sb.auth.currentUser?.id;
        final rows = await _sb
            .from('messages')
            .select()
            .eq('chat_id', chatId)
            .order('sent_at', ascending: true);

        if (currentGen < fetchGeneration) {
          return;
        }

        final msgs = (rows as List)
            .map(
              (d) => ChatMessage.fromSupabase(d as Map<String, dynamic>, myUid),
            )
            .toList();

        // Write-through to Hive MessagesStore
        if (_messagesStore != null) {
          try {
            await _messagesStore!.saveMessages(msgs);
            if (_outboxDaemon != null) {
              for (final m in msgs) {
                if (m.deliveryState.index >= DeliveryState.sent.index) {
                  unawaited(_outboxDaemon!.onMessageConfirmed(m.id));
                }
              }
            }
          } catch (e) {
            debugPrint(
              '[MessagesRepo] Non-fatal message cache save notice: $e',
            );
          }
        }

        if (!controller.isClosed) {
          controller.add(msgs);
        }
      } catch (e, st) {
        if (currentGen == fetchGeneration && !controller.isClosed) {
          debugPrint('[MessagesRepo] Supabase watchChat error: $e');
          controller.addError(e, st);
        }
      }
    }

    void startSubscription() {
      if (_messagesStore != null) {
        try {
          final cached = _messagesStore!.getMessagesForChat(chatId);
          if (cached.isNotEmpty && !controller.isClosed) {
            controller.add(cached);
          }
        } catch (e) {
          debugPrint(
            '[MessagesRepo] Non-fatal local message cache read notice: $e',
          );
        }
      }

      fetchAndEmit();

      channel = _sb.channel('chat_messages:$chatId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: chatId,
            ),
            callback: (_) => fetchAndEmit(),
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              debugPrint(
                '[MessagesRepo] Realtime subscription status: $status, error: $error',
              );
              if (!controller.isClosed && error != null) {
                controller.addError(error);
              }
            } else if (status == RealtimeSubscribeStatus.subscribed) {
              fetchAndEmit();
            }
          });
    }

    void stopSubscription() {
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

    controller = StreamController<List<ChatMessage>>.broadcast(
      onListen: startSubscription,
      onCancel: stopSubscription,
    );

    return controller.stream;
  }

  // ---------------- SEND ----------------

  Future<String> sendMessage(
    String chatId,
    ChatMessage msg, {
    required String otherUserId,
    required String otherName,
    String? otherAvatar,
  }) async {
    final me = msg.senderId;

    await ensureChatDoc(
      chatId: chatId,
      uidA: me,
      uidB: otherUserId,
      title: otherName,
      avatarUrl: otherAvatar,
    );

    if (_messagesStore != null) {
      try {
        await _messagesStore!.saveMessage(
          msg.copyWith(deliveryState: DeliveryState.sending),
        );
      } catch (e) {
        debugPrint('[MessagesRepo] Non-fatal optimistic store save notice: $e');
      }
    }

    if (_chatsStore != null) {
      try {
        await _chatsStore!.updateOptimisticPreview(
          chatId: chatId,
          message: msg,
          currentUserId: me,
          otherUserId: otherUserId,
          otherAvatar: otherAvatar,
        );
      } catch (e) {
        debugPrint(
          '[MessagesRepo] Non-fatal chat summary optimistic update notice: $e',
        );
      }
    }

    if (_outboxDaemon != null) {
      await _outboxDaemon!.enqueueMessage(
        message: msg,
        accountId: me,
        otherUserId: otherUserId,
        otherName: otherName,
        otherAvatar: otherAvatar,
      );
      return msg.id;
    }

    try {
      final payload = <String, dynamic>{
        'id': msg.id,
        'chat_id': chatId,
        'sender_id': me,
        'type': msg.type.name,
        'text': msg.text,
        if (msg.media != null) 'media': msg.media!.toMap(),
        'status': 1, // sent
        'sent_at': msg.sentAt.toUtc().toIso8601String(),
        'is_forwarded': msg.isForwarded,
        if (msg.replyToMessageId != null) 'reply_to_message_id': msg.replyToMessageId,
        if (msg.hasReply)
          'reply_snapshot': {
            if (msg.replyText != null) 'text': msg.replyText,
            if (msg.replySenderName != null) 'sender_name': msg.replySenderName,
            if (msg.replyMediaKind != null) 'media_kind': msg.replyMediaKind,
          },
      };

      try {
        await _sb.from('messages').insert(payload);
      } on PostgrestException catch (e) {
        // Fallback ONLY when database/schema explicitly lacks forward/reply columns or their grants
        final isMissingColumnError = e.code == 'PGRST204' ||
            e.code == '42703' ||
            (e.code == '42501' &&
                e.message.toLowerCase().contains('column') &&
                (e.message.contains('is_forwarded') ||
                    e.message.contains('reply_to_message_id') ||
                    e.message.contains('reply_snapshot')));

        if (isMissingColumnError) {
          debugPrint(
            '[MessagesRepo] Schema missing reply/forward columns, falling back to legacy payload: ${e.message}',
          );
          final fallbackPayload = Map<String, dynamic>.from(payload)
            ..remove('is_forwarded')
            ..remove('reply_to_message_id')
            ..remove('reply_snapshot');
          await _sb.from('messages').insert(fallbackPayload);
        } else {
          rethrow;
        }
      }

      if (_messagesStore != null) {
        try {
          await _messagesStore!.saveMessage(
            msg.copyWith(deliveryState: DeliveryState.sent),
          );
        } catch (_) {}
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await _sb
            .from('messages')
            .select('id, chat_id, sender_id')
            .eq('id', msg.id)
            .maybeSingle();

        if (existing != null &&
            existing['sender_id'] == me &&
            existing['chat_id'] == chatId) {
          if (_messagesStore != null) {
            try {
              await _messagesStore!.saveMessage(
                msg.copyWith(deliveryState: DeliveryState.sent),
              );
            } catch (_) {}
          }
          return msg.id;
        }
      }
      rethrow;
    }

    return msg.id;
  }

  // ---------------- STATUS ----------------

  Future<void> promoteStatusBatch({
    required String chatId,
    required List<String> messageIds,
    required int newStatus,
  }) async {
    if (messageIds.isEmpty) return;

    final toPromote = messageIds
        .where((id) => id.isNotEmpty && !_recentDeliveryAcks.contains(id))
        .toList();
    if (toPromote.isEmpty) return;

    for (final id in toPromote) {
      _recentDeliveryAcks.add(id);
      if (_recentDeliveryAcks.length > 500) {
        _recentDeliveryAcks.remove(_recentDeliveryAcks.first);
      }
    }

    if (_messagesStore != null) {
      final state = DeliveryState.values.firstWhere(
        (s) => s.index == newStatus,
        orElse: () => DeliveryState.delivered,
      );
      for (final id in toPromote) {
        try {
          await _messagesStore!.updateDelivery(id, state);
          if (_chatsStore != null) {
            await _chatsStore!.updateDeliveryStatus(chatId, id, newStatus);
          }
        } catch (_) {}
      }
    }

    final client = _safeSb;
    if (client != null) {
      try {
        await client.rpc(
          'promote_message_status',
          params: {'p_message_ids': toPromote, 'p_new_status': newStatus},
        );
      } catch (e, st) {
        debugPrint('[MessagesRepo] promote_message_status error: $e');
        for (final id in toPromote) {
          _recentDeliveryAcks.remove(id);
        }
        if (_messagesStore == null) {
          debugPrintStack(stackTrace: st);
          rethrow;
        }
      }
    }
  }

  Future<void> markRead(String chatId, String readerUid) async {
    try {
      if (_messagesStore != null) {
        final incoming = _messagesStore!
            .getMessagesForChat(chatId)
            .where(
              (m) =>
                  m.senderId != readerUid &&
                  m.deliveryState.index < DeliveryState.read.index,
            )
            .toList();
        for (final m in incoming) {
          try {
            await _messagesStore!.updateDelivery(m.id, DeliveryState.read);
          } catch (_) {}
        }
      }
      await _sb.rpc('mark_chat_read', params: {'p_chat_id': chatId});
    } catch (e) {
      debugPrint('[MessagesRepo] mark_chat_read error: $e');
      rethrow;
    }
  }

  Future<String?> getDisplayName(String uid) async {
    try {
      final row = await _sb
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      return (row?['display_name'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> markDeliveredIfNeeded({
    required String chatId,
    required String currentUserId,
    required List<ChatMessage> messages,
  }) async {
    final toDeliver = messages
        .where(
          (m) =>
              m.senderId != currentUserId &&
              m.deliveryState.index < DeliveryState.delivered.index,
        )
        .toList();

    if (toDeliver.isEmpty) return;

    await promoteStatusBatch(
      chatId: chatId,
      messageIds: toDeliver.map((m) => m.id).toList(),
      newStatus: DeliveryState.delivered.index,
    );
  }

  Future<ChatModel> getChat(String chatId) async {
    final rows = await _sb
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    final memberIds = (rows as List)
        .map((r) => r['user_id'].toString())
        .toList();
    return ChatModel(id: chatId, members: memberIds);
  }
}
