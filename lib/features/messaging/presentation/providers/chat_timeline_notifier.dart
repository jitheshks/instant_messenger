import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';

class ChatTimelineNotifier extends Notifier<ChatTimelineState> {
  final ChatControllerArgs arg;

  ChatTimelineNotifier(this.arg);

  StreamSubscription<List<ChatMessage>>? _msgSub;
  bool _initInProgress = false;

  bool get initInProgress => _initInProgress;
  bool get hasMore => state.hasMore;
  bool get loadingMore => state.loadingMore;
  DateTime? get lastSentAt => state.lastSentAt;

  @override
  ChatTimelineState build() {
    ref.onDispose(() {
      _msgSub?.cancel();
    });

    final repo = ref.watch(messagesRepositoryProvider);
    final outbox = ref.watch(outboxServiceProvider);
    final store = repo?.messagesStore ??
        HiveDatabaseManager.instance.activeDatabase?.messagesStore;

    // Load from local storage immediately for zero latency
    final cached = store?.getMessagesForChat(arg.chatId) ??
        outbox?.messageCache.getRecent(arg.chatId) ??
        const <ChatMessage>[];

    List<ChatMessage> initialMessages = const [];
    DateTime? initialCursor;

    if (cached.isNotEmpty) {
      initialMessages = cached
          .map((m) => m.copyWith(isIncoming: m.senderId != arg.currentUserId))
          .toList()
        ..sort(_messageSort);
      initialCursor = initialMessages.first.sentAt;
    }

    _bindStream(repo, outbox, arg);

    return ChatTimelineState(
      messages: initialMessages,
      isLoading: initialMessages.isEmpty,
      lastSentAt: initialCursor,
    );
  }

  void _bindStream(
    MessagesRepository? repo,
    OutboxService? outbox,
    ChatControllerArgs arg,
  ) {
    final store = repo?.messagesStore ??
        HiveDatabaseManager.instance.activeDatabase?.messagesStore;

    final stream = store?.watchMessages(arg.chatId) ??
        outbox?.watchForChat(arg.chatId);

    if (stream == null) return;

    _msgSub?.cancel();
    _msgSub = stream.listen((rawList) {
      final mapped = rawList
          .map((m) => m.copyWith(isIncoming: m.senderId != arg.currentUserId))
          .toList()
        ..sort(_messageSort);

      // Unread count tracking for scroll button
      final oldCount = state.messages.length;
      final newCount = mapped.length;
      if (newCount > oldCount) {
        final added = mapped.sublist(oldCount);
        final unreadIncoming =
            added.where((m) => m.isIncoming && !m.isRead).length;
        if (unreadIncoming > 0) {
          try {
            ref
                .read(chatScrollControllerProvider.notifier)
                .onNewMessages(unreadIncoming);
          } catch (_) {}
        }
      }

      // Mark incoming messages as delivered (idempotent)
      repo?.markDeliveredIfNeeded(
        chatId: arg.chatId,
        currentUserId: arg.currentUserId,
        messages: mapped,
      );

      final oldestCursor =
          mapped.isNotEmpty ? mapped.first.sentAt : state.lastSentAt;

      state = state.copyWith(
        messages: mapped,
        isLoading: false,
        lastSentAt: oldestCursor,
      );
    }, onError: (err) {
      debugPrint('[ChatTimelineNotifier] stream notice: $err');
    });
  }

  Future<void> ensureInit({
    required String otherName,
    String? otherAvatar,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_initInProgress || state.isReady) return;
    _initInProgress = true;
    state = state.copyWith(clearError: true);

    try {
      final repo = ref.read(messagesRepositoryProvider);
      if (repo != null && !arg.isGroup && arg.otherUserId.isNotEmpty) {
        await repo
            .ensureChatDoc(
              chatId: arg.chatId,
              uidA: arg.currentUserId,
              uidB: arg.otherUserId,
              title: otherName,
              avatarUrl: otherAvatar,
            )
            .timeout(timeout);
      }

      if (!ref.mounted) return;
      state = state.copyWith(isReady: true, clearError: true);

      // Trigger catch-up sync for this conversation to pull any pending remote messages
      final database = HiveDatabaseManager.instance.activeDatabase;
      if (database?.reconciliationService != null) {
        unawaited(
          database!.reconciliationService!.syncMessages(chatId: arg.chatId),
        );
      }
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(initError: e.toString());
      }
    } finally {
      _initInProgress = false;
    }
  }

  void clearInitError() {
    if (!ref.mounted) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> loadOlder() async {
    if (!state.hasMore || state.loadingMore || state.lastSentAt == null) return;

    state = state.copyWith(loadingMore: true);

    try {
      final repo = ref.read(messagesRepositoryProvider);
      final outbox = ref.read(outboxServiceProvider);
      final store = repo?.messagesStore ??
          HiveDatabaseManager.instance.activeDatabase?.messagesStore;

      if (repo == null) {
        if (ref.mounted) {
          state = state.copyWith(loadingMore: false);
        }
        return;
      }

      final snap = await repo.loadOlderMessages(arg.chatId, state.lastSentAt!);

      if (!ref.mounted) return;

      if (snap.isEmpty) {
        state = state.copyWith(hasMore: false, loadingMore: false);
        return;
      }

      final olderMessages = snap.reversed.toList();

      if (store != null) {
        await store.saveMessages(olderMessages);
      } else if (outbox != null) {
        await outbox.messageCache.prependMessages(olderMessages);
      }

      if (!ref.mounted) return;

      final updatedCursor = snap.last.sentAt;
      final merged = [...olderMessages, ...state.messages];

      state = state.copyWith(
        messages: merged,
        lastSentAt: updatedCursor,
        hasMore: snap.length >= 30,
        loadingMore: false,
      );
    } catch (e, st) {
      debugPrint('[ChatTimelineNotifier] loadOlder error: $e');
      debugPrintStack(stackTrace: st);
      if (ref.mounted) {
        state = state.copyWith(loadingMore: false);
      }
    }
  }

  bool _isMarkingRead = false;

  Future<void> maybeMarkRead([ChatMessage? newest]) async {
    if (_isMarkingRead) return;

    final hasUnread = (newest != null && newest.isIncoming && !newest.isRead) ||
        state.messages.any((m) => m.isIncoming && !m.isRead);
    if (!hasUnread) return;

    _isMarkingRead = true;
    try {
      final repo = ref.read(messagesRepositoryProvider);
      if (repo != null && ref.mounted) {
        await repo.markRead(arg.chatId, arg.currentUserId);
        if (ref.mounted) {
          final updated = state.messages.map((m) {
            if (m.isIncoming && !m.isRead) {
              return m.copyWith(deliveryState: DeliveryState.read);
            }
            return m;
          }).toList();
          state = state.copyWith(messages: updated);
        }
      }
    } catch (e) {
      debugPrint('[ChatTimelineNotifier] maybeMarkRead error: $e');
    } finally {
      _isMarkingRead = false;
    }
  }

  int _messageSort(ChatMessage a, ChatMessage b) {
    if (a.deliveryState == DeliveryState.sending &&
        b.deliveryState != DeliveryState.sending) {
      return 1;
    }
    if (b.deliveryState == DeliveryState.sending &&
        a.deliveryState != DeliveryState.sending) {
      return -1;
    }
    return a.sentAt.compareTo(b.sentAt);
  }
}
