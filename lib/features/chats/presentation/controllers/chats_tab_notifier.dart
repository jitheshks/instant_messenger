import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class ChatsTabState {
  final List<ChatSummary> chats;
  final bool isLoading;
  final bool isReady;
  final bool isBound;
  final String? errorMessage;
  final bool isOffline;
  final bool isBackendUnavailable;
  final bool isRealtimeDisconnected;

  const ChatsTabState({
    this.chats = const [],
    this.isLoading = true,
    this.isReady = false,
    this.isBound = false,
    this.errorMessage,
    this.isOffline = false,
    this.isBackendUnavailable = false,
    this.isRealtimeDisconnected = false,
  });

  int get totalUnread => chats.fold<int>(0, (acc, chat) => acc + chat.unread);
  bool get hasError => errorMessage != null;
  bool get hasChats => chats.isNotEmpty;
  bool get isConnecting => isBackendUnavailable;

  ChatsTabState copyWith({
    List<ChatSummary>? chats,
    bool? isLoading,
    bool? isReady,
    bool? isBound,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOffline,
    bool? isBackendUnavailable,
    bool? isRealtimeDisconnected,
  }) {
    return ChatsTabState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      isReady: isReady ?? this.isReady,
      isBound: isBound ?? this.isBound,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      isBackendUnavailable: isBackendUnavailable ?? this.isBackendUnavailable,
      isRealtimeDisconnected:
          isRealtimeDisconnected ?? this.isRealtimeDisconnected,
    );
  }
}

class ChatsTabNotifier extends Notifier<ChatsTabState> {
  final GlobalKey<AnimatedListState> listKey = GlobalKey<AnimatedListState>();

  StreamSubscription<List<ChatSummary>>? _sub;
  StreamSubscription<List<ChatSummary>>? _localSub;
  StreamSubscription<RealtimeSubscribeStatus>? _realtimeSub;
  StreamSubscription<RealtimeConnectionStatus>? _realtimeConnectionSub;
  StreamSubscription<NetworkInterfaceStatus>? _connectivitySub;
  StreamSubscription<BackendReachabilityStatus>? _reachabilitySub;
  bool _postFrameRequested = false;
  String? _boundUid;

  @override
  ChatsTabState build() {
    final connectivity = ref.watch(connectivityServiceProvider);
    _connectivitySub = connectivity.onStatusChanged.listen((status) {
      _onNetworkInterfaceChanged(status);
    });
    _reachabilitySub = connectivity.onReachabilityChanged.listen((reachability) {
      _onReachabilityChanged(reachability);
    });

    ref.onDispose(() {
      _sub?.cancel();
      _localSub?.cancel();
      _realtimeSub?.cancel();
      _realtimeConnectionSub?.cancel();
      _connectivitySub?.cancel();
      _reachabilitySub?.cancel();
    });
    return const ChatsTabState();
  }

  List<ChatSummary> get chats => state.chats;
  bool get isReady => state.isReady;
  bool get isBound => state.isBound;
  bool get isLoading => state.isLoading;
  String? get errorMessage => state.errorMessage;
  bool get isOffline => state.isOffline;
  bool get isBackendUnavailable => state.isBackendUnavailable;
  bool get isRealtimeDisconnected => state.isRealtimeDisconnected;
  int get totalUnread => state.totalUnread;

  void reset() {
    _sub?.cancel();
    _sub = null;
    _localSub?.cancel();
    _localSub = null;
    _realtimeSub?.cancel();
    _realtimeSub = null;
    _realtimeConnectionSub?.cancel();
    _realtimeConnectionSub = null;
    _postFrameRequested = false;
    _boundUid = null;
    state = const ChatsTabState(
      chats: [],
      isLoading: false,
      isReady: false,
      isBound: false,
    );
  }

  void unbind() => reset();

  void ensureBound(String uid) {
    if ((state.isBound || _postFrameRequested) && _boundUid == uid) return;
    _postFrameRequested = true;
    _boundUid = uid;
    unawaited(bind(uid));
  }

  Future<void> bind(String currentUserId) async {
    _boundUid = currentUserId;
    state = state.copyWith(
      isBound: true,
      isLoading: true,
      clearErrorMessage: true,
    );

    // 1. Immediately emit locally cached conversations and listen for local updates
    try {
      ref.read(contactsDataControllerProvider.notifier).refreshIfPermitted();
    } catch (_) {}

    try {
      final chatsStore =
          HiveDatabaseManager.instance.activeDatabase?.chatsStore;
      if (chatsStore != null) {
        final cached = chatsStore.getAllChatSummaries();
        debugPrint('[ChatsTabNotifier] hive chats=${cached.length}');
        if (cached.isNotEmpty) {
          state = state.copyWith(
            chats: List.unmodifiable(cached),
            isReady: true,
          );
        }

        _localSub?.cancel();
        _localSub = chatsStore.watchChatSummaries().listen((localChats) {
          if (localChats.isNotEmpty || !state.isReady) {
            state = state.copyWith(
              chats: List.unmodifiable(localChats),
              isReady: true,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('[ChatsTabNotifier] Failed to load cached chats: $e');
    }

    // 2. Subscribe to Supabase conversations stream and Realtime status
    final repo = ref.read(chatsRepositoryProvider);
    final activeDb = HiveDatabaseManager.instance.activeDatabase;
    RealtimeConnectionManager? rcm;
    try {
      if (activeDb?.chatsStore != null) {
        repo.attachChatsStore(activeDb!.chatsStore);
      }
      if (activeDb?.realtimeConnectionManager != null) {
        repo.attachConnectionManager(activeDb!.realtimeConnectionManager!);
      }
      rcm = repo.connectionManager ?? activeDb?.realtimeConnectionManager;
    } catch (_) {
      rcm = activeDb?.realtimeConnectionManager;
    }

    _realtimeSub?.cancel();
    _realtimeConnectionSub?.cancel();
    if (rcm != null) {
      _realtimeConnectionSub = rcm.onStatusChanged.listen((status) {
        _onRealtimeConnectionStatusChanged(status);
      });
      _onRealtimeConnectionStatusChanged(rcm.status);
    } else {
      _realtimeSub = repo.onRealtimeStatusChanged.listen((status) {
        final isDisconnected = status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut;
        setRealtimeDisconnected(isDisconnected);
      });
    }

    _sub?.cancel();
    _sub = repo
        .watchUserChats(currentUserId)
        .listen(
          (newChats) {
            _applyUpdates(newChats);
          },
          onError: (err) {
            debugPrint('[ChatsTabNotifier] watch error: $err');
            _handleError(err);
          },
        );
  }

  void _onRealtimeConnectionStatusChanged(RealtimeConnectionStatus status) {
    final connectivity = ref.read(connectivityServiceProvider);
    final isDisconnected = (status == RealtimeConnectionStatus.disconnected ||
            status == RealtimeConnectionStatus.connecting) &&
        connectivity.hasNetworkInterface &&
        connectivity.backendReachabilityStatus ==
            BackendReachabilityStatus.reachable;
    setRealtimeDisconnected(isDisconnected);
  }

  void setRealtimeDisconnected(bool disconnected) {
    if (state.isRealtimeDisconnected != disconnected) {
      state = state.copyWith(isRealtimeDisconnected: disconnected);
    }
  }

  void _onNetworkInterfaceChanged(NetworkInterfaceStatus status) {
    if (!status.hasInterface) {
      state = state.copyWith(
        isOffline: true,
        isBackendUnavailable: false,
        errorMessage: "You are offline. Please check your internet connection.",
      );
    } else {
      if (state.isOffline) {
        state = state.copyWith(
          isOffline: false,
          clearErrorMessage: true,
        );
        unawaited(refresh());
      }
    }
  }

  void _onReachabilityChanged(BackendReachabilityStatus reachability) {
    final connectivity = ref.read(connectivityServiceProvider);
    if (reachability == BackendReachabilityStatus.reachable) {
      if (state.isBackendUnavailable) {
        state = state.copyWith(
          isBackendUnavailable: false,
          clearErrorMessage: true,
        );
        unawaited(refresh());
      }
    } else if (reachability == BackendReachabilityStatus.unreachable &&
        connectivity.hasNetworkInterface) {
      if (state.errorMessage != null && !state.isOffline) {
        state = state.copyWith(
          isBackendUnavailable: true,
          isOffline: false,
          errorMessage: "Connecting to messenger services...",
        );
      }
    }
  }

  void _applyUpdates(List<ChatSummary> newChats) {
    state = state.copyWith(
      chats: List.unmodifiable(newChats),
      isReady: true,
      isLoading: false,
      clearErrorMessage: true,
      isOffline: false,
      isBackendUnavailable: false,
    );
    HiveDatabaseManager.instance.activeDatabase?.chatsStore
        .saveChatSummaries(newChats);
  }

  void _handleError(Object err) {
    // 1. PostgREST database-level error: server was reached and responded with an error
    if (err is PostgrestException) {
      final errorMsg = _formatPostgrestError(err);
      state = state.copyWith(
        isReady: true,
        isLoading: false,
        isOffline: false,
        isBackendUnavailable: false,
        errorMessage: errorMsg,
      );
      return;
    }

    final connectivity = ref.read(connectivityServiceProvider);
    final hasInterface = connectivity.hasNetworkInterface;

    // 2. Physical network interface is disconnected
    if (!hasInterface) {
      state = state.copyWith(
        isReady: true,
        isLoading: false,
        isOffline: true,
        isBackendUnavailable: false,
        errorMessage: "You are offline. Please check your internet connection.",
      );
      return;
    }

    // 3. Physical network is connected, but Supabase backend is unreachable/timed out
    if (_isNetworkError(err)) {
      state = state.copyWith(
        isReady: true,
        isLoading: false,
        isOffline: false,
        isBackendUnavailable: true,
        errorMessage: "Connecting to messenger services...",
      );
      return;
    }

    // 4. Other unexpected error
    state = state.copyWith(
      isReady: true,
      isLoading: false,
      isOffline: false,
      isBackendUnavailable: false,
      errorMessage: "Failed to load chats. Tap to retry.",
    );
  }

  bool _isNetworkError(Object err) {
    if (err is SocketException || err is TimeoutException) return true;
    final str = err.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('network is unreachable') ||
        str.contains('connection timed out') ||
        str.contains('failed host lookup') ||
        str.contains('clientexception') ||
        str.contains('connection refused');
  }

  String _formatPostgrestError(PostgrestException err) {
    if (err.code == 'PGRST205' || err.code == '42P01') {
      return "Chats service is currently initializing. Please try again in a moment.";
    }
    if (err.message.isNotEmpty) {
      return err.message;
    }
    return "Failed to load chats. Tap to retry.";
  }

  /// Pull-to-refresh or retry manual action.
  Future<void> refresh() async {
    final uid = _boundUid ?? SupabaseConfig.currentUserId ?? '';
    if (uid.isEmpty) return;

    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    final connectivity = ref.read(connectivityServiceProvider);
    if (connectivity.hasNetworkInterface) {
      unawaited(connectivity.checkBackendReachability(force: true));
    }

    try {
      final repo = ref.read(chatsRepositoryProvider);
      final newChats = await repo.fetchUserChats(uid);
      _applyUpdates(newChats);
    } catch (e) {
      debugPrint('[ChatsTabNotifier] refresh error: $e');
      _handleError(e);
    }
  }

  Future<void> retry() async {
    final rcm =
        HiveDatabaseManager.instance.activeDatabase?.realtimeConnectionManager;
    if (rcm != null) {
      unawaited(rcm.requestManualRetry());
    }
    return refresh();
  }

  Future<void> deleteChat(String chatId) async {
    await ref.read(chatsRepositoryProvider).leaveChat(chatId);
    final updated = state.chats.where((c) => c.id != chatId).toList();
    state = state.copyWith(chats: List.unmodifiable(updated));
    HiveDatabaseManager.instance.activeDatabase?.chatsStore
        .saveChatSummaries(updated);
  }

  Future<void> deleteSelectedChats(Iterable<String> chatIds) =>
      deleteChatsBatch(chatIds);

  Future<void> deleteChatsBatch(Iterable<String> chatIds) async {
    final toDelete = chatIds.toSet();
    final repo = ref.read(chatsRepositoryProvider);
    for (final id in toDelete) {
      await repo.leaveChat(id);
    }
    final updated = state.chats.where((c) => !toDelete.contains(c.id)).toList();
    state = state.copyWith(chats: List.unmodifiable(updated));
    HiveDatabaseManager.instance.activeDatabase?.chatsStore
        .saveChatSummaries(updated);
  }
}
