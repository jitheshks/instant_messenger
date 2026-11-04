// lib/features/chats/presentation/controllers/communities_tab_notifier.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/chat_summary.dart';
import '../providers/chats_providers.dart';

class CommunitiesTabState {
  final bool isLoading;
  final String? errorMessage;
  final List<ChatSummary> groups;

  const CommunitiesTabState({
    this.isLoading = false,
    this.errorMessage,
    this.groups = const [],
  });

  CommunitiesTabState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<ChatSummary>? groups,
  }) {
    return CommunitiesTabState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      groups: groups ?? this.groups,
    );
  }
}

class CommunitiesTabNotifier extends Notifier<CommunitiesTabState> {
  StreamSubscription<List<ChatSummary>>? _groupsSub;

  @override
  CommunitiesTabState build() {
    final repo = ref.watch(chatsRepositoryProvider);
    _groupsSub?.cancel();

    state = const CommunitiesTabState(isLoading: true);

    _groupsSub = repo.watchUserGroups().listen(
      (groups) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: null,
          groups: groups,
        );
      },
      onError: (err) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: err.toString(),
        );
      },
    );

    ref.onDispose(() {
      _groupsSub?.cancel();
    });

    return state;
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(chatsRepositoryProvider);
      final groups = await repo.fetchUserGroups();
      state = state.copyWith(
        isLoading: false,
        errorMessage: null,
        groups: groups,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
}
