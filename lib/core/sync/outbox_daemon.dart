import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/network/retry_policy.dart';
import 'package:instant_messenger/core/persistence/models/outbox_entry.dart';
import 'package:instant_messenger/core/persistence/stores/chats_store.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/core/persistence/stores/outbox_store.dart';
import 'package:instant_messenger/core/sync/outbox_session_gate.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef MutationHandler = Future<bool> Function(OutboxEntry entry);

/// Durable background daemon that processes queued message mutations with
/// bounded exponential backoff, jitter, connectivity awareness, and crash recovery.
class OutboxDaemon {
  final String accountId;
  final OutboxStore outboxStore;
  final MessagesStore messagesStore;
  ChatsStore? chatsStore;
  final ConnectivityService connectivityService;
  final RetryPolicy retryPolicy;
  final MutationHandler? _customHandler;
  final SupabaseClient? _supabaseClient;
  final OutboxSessionGate _gate = OutboxSessionGate();

  bool _running = false;
  bool _isDraining = false;
  Future<void>? _drainFuture;
  StreamSubscription<NetworkInterfaceStatus>? _connectivitySub;
  StreamSubscription<BackendReachabilityStatus>? _reachabilitySub;
  Timer? _scheduledTimer;

  bool get isRunning => _running;
  bool get isDraining => _isDraining;
  OutboxSessionGate get sessionGate => _gate;

  OutboxDaemon({
    required this.accountId,
    required this.outboxStore,
    required this.messagesStore,
    this.chatsStore,
    ConnectivityService? connectivityService,
    RetryPolicy? retryPolicy,
    MutationHandler? customHandler,
    SupabaseClient? supabaseClient,
  }) : connectivityService = connectivityService ?? ConnectivityService(),
       retryPolicy = retryPolicy ??
           RetryPolicy(
             maxDelay: const Duration(seconds: 60),
           ),
       _customHandler = customHandler,
       _supabaseClient = supabaseClient;

  SupabaseClient get _sb => _supabaseClient ?? Supabase.instance.client;

  SupabaseClient? get _safeSb {
    if (_supabaseClient != null) return _supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Starts the daemon and begins listening for connectivity changes.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // 1. Recover any abandoned in-flight mutations from a previous crash/termination
    try {
      await outboxStore.recoverInFlight(maxRetries: retryPolicy.maxAttempts);
    } catch (e) {
      debugPrint('[OutboxDaemon] Crash recovery error: $e');
    }

    // 2. Listen to connectivity transitions (offline -> online wakes daemon)
    _connectivitySub = connectivityService.onStatusChanged.listen(
      (status) async {
        if (status.hasInterface && _running) {
          debugPrint(
            '[OutboxDaemon] Network interface restored -> resetting schedule & triggering drain',
          );
          await _gate.run(() async => outboxStore.resetScheduledForQueued());
          triggerDrain();
        }
      },
      onError: (err) {
        debugPrint('[OutboxDaemon] Connectivity stream notice: $err');
      },
    );

    // 2b. Listen to backend reachability transitions (unreachable -> reachable wakes daemon)
    _reachabilitySub = connectivityService.onReachabilityChanged.listen(
      (reachability) async {
        if (reachability == BackendReachabilityStatus.reachable && _running) {
          debugPrint(
            '[OutboxDaemon] Backend reachability restored -> resetting schedule & triggering drain',
          );
          await _gate.run(() async => outboxStore.resetScheduledForQueued());
          triggerDrain();
        }
      },
      onError: (err) {
        debugPrint('[OutboxDaemon] Reachability stream notice: $err');
      },
    );

    // 3. Trigger initial drain attempt
    triggerDrain();
  }

  /// Stops the daemon, cancels background timers, and safely coordinates in-flight
  /// store operations to prevent writes to closed boxes.
  Future<void> stop({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    _running = false;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _reachabilitySub?.cancel();
    _reachabilitySub = null;

    if (_isDraining && _drainFuture != null) {
      try {
        await _drainFuture!.timeout(timeout);
      } catch (_) {}
    }

    await _gate.close(timeout: timeout);
    if (outboxStore.box.isOpen) {
      try {
        await outboxStore.recoverInFlight();
      } catch (_) {}
    }
  }

  void dispose() {
    unawaited(stop());
  }

  /// Idempotently enqueues a text or media message mutation into the outbox.
  Future<void> enqueueMessage({
    required ChatMessage message,
    required String accountId,
    String? otherUserId,
    String? otherName,
    String? otherAvatar,
  }) async {
    if (_gate.isClosed) return;

    await _gate.run(() async {
      // Check if operation already exists (idempotency guard)
      final existing = outboxStore.getById(message.id);
      if (existing != null) {
        debugPrint(
          '[OutboxDaemon] Message ${message.id} already in outbox. Enqueue skipped.',
        );
        return;
      }

      final payload = message.toMap();
      if (otherUserId != null && otherUserId.isNotEmpty) {
        payload['otherUserId'] = otherUserId;
      }
      if (otherName != null && otherName.isNotEmpty) {
        payload['otherName'] = otherName;
      }
      if (otherAvatar != null && otherAvatar.isNotEmpty) {
        payload['otherAvatar'] = otherAvatar;
      }

      final entry = OutboxEntry(
        id: message.id,
        accountId: accountId,
        mutationType: 'send_message',
        targetId: message.id,
        payloadJson: jsonEncode(payload),
        createdAt: DateTime.now(),
        retryCount: 0,
        nextAttemptAt: DateTime.now(),
        state: 'queued',
      );

      await outboxStore.enqueue(entry);
    });

    // Trigger immediate drain (fire and forget, returns control to UI)
    triggerDrain();
  }

  /// Triggers a queue drain cycle. Guarded against concurrent runs.
  void triggerDrain() {
    if (!_running || _isDraining || _gate.isClosed) return;

    if (!connectivityService.hasNetworkInterface) {
      debugPrint(
        '[OutboxDaemon] No active network interface. Awaiting connectivity.',
      );
      return;
    }

    if (connectivityService.backendReachabilityStatus ==
        BackendReachabilityStatus.unreachable) {
      debugPrint(
        '[OutboxDaemon] Backend reachability is unreachable. Pausing dispatch until reachable.',
      );
      return;
    }

    final future = _drainQueue();
    _drainFuture = future;
    unawaited(future);
  }

  Future<void> _drainQueue() async {
    if (_isDraining || !_running || _gate.isClosed) return;
    _isDraining = true;

    try {
      while (_running &&
          !_gate.isClosed &&
          connectivityService.hasNetworkInterface &&
          connectivityService.backendReachabilityStatus !=
              BackendReachabilityStatus.unreachable) {
        final now = DateTime.now();
        final scheduled = await _gate.run(
          () async => outboxStore.getScheduled(now, limit: 10),
        );

        if (scheduled == null || scheduled.isEmpty) break;

        for (final entry in scheduled) {
          if (!_running || _gate.isClosed) break;

          // 1. Lease the mutation under the session gate
          final leased = await _gate.run(() async {
            await outboxStore.updateState(entry.id, 'in_flight');
            return true;
          });
          if (leased != true) break;

          // 2. Dispatch the mutation over network (outside gate.run so network does not block gate.close())
          try {
            final success = await _dispatch(entry);

            // 3. Complete the mutation under the session gate
            await _gate.run(() async {
              if (success) {
                await outboxStore.remove(entry.id);
                await messagesStore.updateDelivery(
                  entry.targetId,
                  DeliveryState.sent,
                );
                if (chatsStore != null) {
                  final msg = messagesStore.getMessage(entry.targetId);
                  if (msg != null && msg.chatId.isNotEmpty) {
                    await chatsStore!.updateDeliveryStatus(
                      msg.chatId,
                      entry.targetId,
                      1,
                    );
                  }
                }
                debugPrint(
                  '[OutboxDaemon] Mutation ${entry.id} completed successfully',
                );
              } else {
                await _handleFailure(
                  entry,
                  Exception('Dispatcher returned false'),
                );
              }
            });
          } catch (e) {
            // 4. Handle failure under the session gate
            await _gate.run(() async {
              await _handleFailure(entry, e);
            });
          }
        }
      }

      // Schedule next wakeup for future retry items if any remain
      if (_running && !_gate.isClosed) {
        _scheduleNextWakeup();
      }
    } finally {
      _isDraining = false;
    }
  }

  Future<bool> _dispatch(OutboxEntry entry) async {
    final handler = _customHandler;
    if (handler != null) {
      return await handler(entry);
    }

    if (entry.mutationType == 'send_message') {
      return await _dispatchSendMessage(entry);
    }

    return true;
  }

  Future<bool> _dispatchSendMessage(OutboxEntry entry) async {
    final Map<String, dynamic> payload = jsonDecode(entry.payloadJson);
    final msg = ChatMessage.fromMap(payload);

    // 1. Account Ownership Validation (Release-safe runtime check)
    if (entry.accountId != accountId) {
      debugPrint(
        '[OutboxDaemon] Rejecting mutation ${entry.id}: entry accountId (${entry.accountId}) mismatches daemon accountId ($accountId)',
      );
      throw PermanentOutboxException(
        'Mutation account mismatch: expected $accountId, got ${entry.accountId}',
      );
    }

    // 2. Message Sender Validation (Release-safe runtime check)
    if (msg.senderId != accountId) {
      debugPrint(
        '[OutboxDaemon] Rejecting mutation ${entry.id}: senderId (${msg.senderId}) mismatches daemon accountId ($accountId)',
      );
      throw PermanentOutboxException(
        'Message sender mismatch: expected $accountId, got ${msg.senderId}',
      );
    }

    // 3. Active Session Validation: ensure current auth session matches account identity
    final currentAuthUid = _safeSb?.auth.currentUser?.id;
    if (currentAuthUid != null && currentAuthUid != accountId) {
      debugPrint(
        '[OutboxDaemon] Aborting dispatch for mutation ${entry.id}: active auth session differs from account ($accountId)',
      );
      throw const AuthSessionMismatchException(
        'Active auth session does not match account identity',
      );
    }

    // 4. Idempotency Check: if message is already confirmed sent locally, complete it
    final localMsg = messagesStore.getMessage(msg.id);
    if (localMsg != null &&
        localMsg.deliveryState.index >= DeliveryState.sent.index) {
      return true;
    }

    try {
      final payload = <String, dynamic>{
        'id': msg.id,
        'chat_id': msg.chatId,
        'sender_id': msg.senderId, // Always msg.senderId (verified == accountId)
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
            '[OutboxDaemon] Schema missing reply/forward columns, falling back to legacy payload: ${e.message}',
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

      return true;
    } on PostgrestException catch (e) {
      // 5. Duplicate Key Recovery (SQLSTATE 23505)
      if (e.code == '23505') {
        try {
          final existing = await _sb
              .from('messages')
              .select('id, chat_id, sender_id')
              .eq('id', msg.id)
              .maybeSingle();

          if (existing != null &&
              existing['sender_id'] == (msg.senderId) &&
              existing['chat_id'] == msg.chatId) {
            debugPrint(
              '[OutboxDaemon] Idempotent recovery for message ${msg.id} (23505 verified)',
            );
            return true;
          }
        } catch (_) {}
        throw PermanentOutboxException(
          'Unresolvable unique constraint violation: ${e.message}',
        );
      }

      // Permanent RLS or validation errors should not retry endlessly
      if (e.code == '42501' || e.code == '22023') {
        debugPrint(
          '[OutboxDaemon] Permanent PostgREST error: ${e.message} (${e.code})',
        );
        throw PermanentOutboxException(e.message);
      }

      rethrow;
    }
  }

  Future<void> _handleFailure(OutboxEntry entry, Object error) async {
    final isPermanent =
        error is PermanentOutboxException ||
        (error is PostgrestException &&
            (error.code == '42501' ||
                error.code == '22023' ||
                error.code == '22P02' ||
                error.code == '23505' ||
                error.code == '23503'));

    final nextRetry = entry.retryCount + 1;

    if (isPermanent) {
      debugPrint(
        '[OutboxDaemon] Mutation ${entry.id} failed permanently: $error',
      );
      await outboxStore.updateState(
        entry.id,
        'exhausted',
        retryCount: nextRetry,
      );
      await messagesStore.updateDelivery(
        entry.targetId,
        DeliveryState.sending,
        failure: MessageFailureReason.serverFailed,
      );
    } else {
      // Transient error: never transition to exhausted solely due to retry count.
      final delay = retryPolicy.calculateDelay(nextRetry);
      final nextAttemptAt = DateTime.now().add(delay);

      debugPrint(
        '[OutboxDaemon] Transient failure on ${entry.id}. Retrying in ${delay.inSeconds}s (attempt $nextRetry)',
      );

      await outboxStore.updateState(
        entry.id,
        'queued',
        nextAttemptAt: nextAttemptAt,
        retryCount: nextRetry,
      );
    }
  }

  void _scheduleNextWakeup() {
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    if (!_running || _gate.isClosed) return;

    if (connectivityService.backendReachabilityStatus ==
        BackendReachabilityStatus.unreachable) {
      // Do not schedule a timer while backend is known unreachable;
      // onReachabilityChanged will wake the daemon once backend is reachable.
      return;
    }

    final queued =
        outboxStore.getAll().where((e) => e.state == 'queued').toList()
          ..sort((a, b) => a.nextAttemptAt.compareTo(b.nextAttemptAt));

    if (queued.isNotEmpty && _running && !_gate.isClosed) {
      final nextAttempt = queued.first.nextAttemptAt;
      final now = DateTime.now();
      final waitDuration = nextAttempt.isAfter(now)
          ? nextAttempt.difference(now)
          : Duration.zero;

      _scheduledTimer = Timer(waitDuration, triggerDrain);
    }
  }

  /// Notifies the daemon that a message was confirmed via Realtime or external channel.
  Future<void> onMessageConfirmed(String messageId) async {
    await _gate.run(() async {
      final entry = outboxStore.getById(messageId);
      if (entry != null) {
        if (entry.mutationType == 'send_message') {
          await outboxStore.remove(messageId);
          await messagesStore.updateDelivery(messageId, DeliveryState.sent);
          if (chatsStore != null) {
            final msg = messagesStore.getMessage(messageId);
            if (msg != null && msg.chatId.isNotEmpty) {
              await chatsStore!.updateDeliveryStatus(msg.chatId, messageId, 1);
            }
          }
          debugPrint(
            '[OutboxDaemon] Message $messageId confirmed externally. Removed from outbox.',
          );
        } else {
          debugPrint(
            '[OutboxDaemon] Preserving outbox mutation $messageId with type "${entry.mutationType}" during message confirmation.',
          );
        }
      } else {
        // Entry was already dispatched or confirmed externally
        await messagesStore.updateDelivery(messageId, DeliveryState.sent);
        if (chatsStore != null) {
          final msg = messagesStore.getMessage(messageId);
          if (msg != null && msg.chatId.isNotEmpty) {
            await chatsStore!.updateDeliveryStatus(msg.chatId, messageId, 1);
          }
        }
      }
    });
  }

  /// Manually retries a queued or exhausted mutation.
  Future<void> retryExhausted(String id) async {
    if (!_running || _gate.isClosed) return;
    await _gate.run(() async {
      final entry = outboxStore.getById(id);
      if (entry != null) {
        await outboxStore.updateState(
          id,
          'queued',
          nextAttemptAt: DateTime.now(),
          retryCount: 0,
        );
        await messagesStore.updateDelivery(
          entry.targetId,
          DeliveryState.sending,
          failure: null,
        );
        triggerDrain();
      }
    });
  }
}

/// Thrown when an outbox mutation encounters a non-recoverable error.
class PermanentOutboxException implements Exception {
  final String message;
  const PermanentOutboxException(this.message);

  @override
  String toString() => 'PermanentOutboxException: $message';
}

/// Thrown when an active authentication session differs from the mutation's account.
class AuthSessionMismatchException implements Exception {
  final String message;
  const AuthSessionMismatchException([
    this.message = 'Active auth session does not match account identity',
  ]);

  @override
  String toString() => 'AuthSessionMismatchException: $message';
}
