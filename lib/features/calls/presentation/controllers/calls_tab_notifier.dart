// lib/features/calls/presentation/controllers/calls_tab_notifier.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import '../../domain/models/call_record.dart';
import '../providers/calls_providers.dart';

class CallsTabState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int nextOffset;
  final String? errorMessage;
  final List<CallRecord> calls;

  const CallsTabState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.errorMessage,
    this.calls = const [],
  });

  CallsTabState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? nextOffset,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<CallRecord>? calls,
  }) {
    return CallsTabState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextOffset: nextOffset ?? this.nextOffset,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      calls: calls ?? this.calls,
    );
  }
}

class CallsTabNotifier extends Notifier<CallsTabState> {
  static const int pageSize = 30;
  StreamSubscription<List<CallRecord>>? _historySubscription;

  @override
  CallsTabState build() {
    final repository = ref.watch(callsRepositoryProvider);
    final activeDb = HiveDatabaseManager.instance.activeDatabase;
    if (activeDb?.realtimeConnectionManager != null) {
      repository.attachConnectionManager(activeDb!.realtimeConnectionManager!);
    }

    _historySubscription?.cancel();

    state = const CallsTabState(isLoading: true, hasMore: true, nextOffset: 0);

    _historySubscription = repository.watchCallHistory().listen(
      (incomingCalls) {
        // Deduplicate and merge incoming realtime/catch-up calls with existing loaded calls
        final map = {for (final c in state.calls) c.id: c};
        for (final c in incomingCalls) {
          map[c.id] = c;
        }
        final merged = map.values.toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

        state = state.copyWith(
          isLoading: false,
          clearErrorMessage: true,
          calls: merged,
          nextOffset: merged.length,
          hasMore: incomingCalls.length >= pageSize,
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
      _historySubscription?.cancel();
    });

    return state;
  }

  /// Triggers a manual pull-to-refresh, reloading the initial page.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final repository = ref.read(callsRepositoryProvider);
      final calls = await repository.fetchCallHistory(limit: pageSize, offset: 0);
      state = state.copyWith(
        isLoading: false,
        clearErrorMessage: true,
        calls: calls,
        nextOffset: calls.length,
        hasMore: calls.length >= pageSize,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Bounded pagination: loads older call records.
  Future<void> loadOlder() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final repository = ref.read(callsRepositoryProvider);
      final olderCalls = await repository.fetchCallHistory(
        limit: pageSize,
        offset: state.nextOffset,
      );

      final map = {for (final c in state.calls) c.id: c};
      for (final c in olderCalls) {
        map[c.id] = c;
      }
      final merged = map.values.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      state = state.copyWith(
        isLoadingMore: false,
        calls: merged,
        nextOffset: state.nextOffset + olderCalls.length,
        hasMore: olderCalls.length >= pageSize,
      );
    } catch (e) {
      debugPrint('[CallsTabNotifier] Error loading older call records: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }
}
