// lib/features/chats/presentation/providers/chats_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/chats_tab_notifier.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/communities_tab_notifier.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/navigation_notifier.dart';
import 'package:instant_messenger/features/messaging/presentation/controllers/selection_notifier.dart';

/// Provider for the [ChatsRepository] managing conversation summaries.
final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final repo = ChatsRepository(supabaseClient: supabase);
  final activeDb = HiveDatabaseManager.instance.activeDatabase;
  if (activeDb?.chatsStore != null) {
    repo.attachChatsStore(activeDb!.chatsStore);
  }
  if (activeDb?.realtimeConnectionManager != null) {
    repo.attachConnectionManager(activeDb!.realtimeConnectionManager!);
  }
  return repo;
});

/// Provider for the conversation list state on the Chats tab.
final chatsTabControllerProvider =
    NotifierProvider<ChatsTabNotifier, ChatsTabState>(ChatsTabNotifier.new);

/// Semantic alias for [chatsTabControllerProvider].
final chatsTabNotifierProvider = chatsTabControllerProvider;

/// Provider for conversation multi-selection state on the Chats tab.
final chatsTabSelectionControllerProvider =
    NotifierProvider<ChatsTabSelectionNotifier, Set<String>>(
      ChatsTabSelectionNotifier.new,
    );

/// Provider for active bottom navigation tab index.
final tabControllerModelProvider = NotifierProvider<NavigationNotifier, int>(
  NavigationNotifier.new,
);

/// Provider for groups/communities state on the Communities tab.
final communitiesTabControllerProvider =
    NotifierProvider<CommunitiesTabNotifier, CommunitiesTabState>(
  CommunitiesTabNotifier.new,
);
