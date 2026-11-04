import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/app/navigation/navigation_config.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/chats_badge_icon.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/delete_chats_dialog.dart';
import 'package:instant_messenger/shared/widgets/badges/small_dot_badge_icon.dart';
import 'package:instant_messenger/shared/widgets/bars/search_bar_notifier.dart';
import 'package:instant_messenger/shared/widgets/bars/searchable_selectable_app_bar.dart';
import 'package:instant_messenger/shared/widgets/menus/tab_menu.dart';

class TabScaffold extends ConsumerWidget {
  final Widget child; // ShellRoute's active child route
  const TabScaffold({required this.child, super.key});

  static List<String> get _tabRoots => BottomNavigationConfig.visiblePaths;

  bool _isTabRoute(String loc) => BottomNavigationConfig.isTabRoute(loc);

  int _indexFor(String loc) => BottomNavigationConfig.indexForLocation(loc);

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    int activeTab,
  ) {
    final selection = ref.watch(chatsTabSelectionControllerProvider);
    final selectionNotifier =
        ref.read(chatsTabSelectionControllerProvider.notifier);
    final chatsState = ref.watch(chatsTabControllerProvider);
    final chatsNotifier = ref.read(chatsTabControllerProvider.notifier);

    final visibleItems = BottomNavigationConfig.visibleItems;
    final activeItem = (activeTab >= 0 && activeTab < visibleItems.length)
        ? visibleItems[activeTab]
        : NavigationTabItem.chats;

    switch (activeItem) {
      case NavigationTabItem.chats:
        return SearchableSelectableAppBar(
          title: 'Chats',
          searchHint: 'Search chats',
          normalActions: (_) => const [TabMenu(kind: TabKind.chats)],
          selectionMode: selection.isNotEmpty,
          selectedCount: selection.length,
          onCloseSelection: () => selectionNotifier.clear(),
          onSelectAll: () =>
              selectionNotifier.selectAll(chatsState.chats.map((c) => c.id)),
          selectionActions: () => [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ids = selection.toList();
                final confirm = await showDeleteChatDialog(context, ids.length);
                if (confirm != null) {
                  await chatsNotifier.deleteSelectedChats(ids);
                  if (!context.mounted) return;
                  selectionNotifier.clear();
                }
              },
            ),
          ],
        );
      case NavigationTabItem.updates:
        return SearchableSelectableAppBar(
          title: 'Updates',
          searchHint: 'Search updates',
          normalActions: (startSearch) => [
            IconButton(onPressed: startSearch, icon: const Icon(Icons.search)),
            const TabMenu(kind: TabKind.updates),
          ],
        );
      case NavigationTabItem.communities:
        return SearchableSelectableAppBar(
          title: 'Communities',
          searchHint: 'Search communities',
          normalActions: (_) => const [TabMenu(kind: TabKind.communities)],
        );
      case NavigationTabItem.calls:
        return SearchableSelectableAppBar(
          title: 'Calls',
          searchHint: 'Search calls',
          normalActions: (startSearch) => [
            IconButton(onPressed: startSearch, icon: const Icon(Icons.search)),
            const TabMenu(kind: TabKind.calls),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = GoRouterState.of(context);
    final loc = state.uri.toString();
    final isVisibleTab = BottomNavigationConfig.isVisibleTabRoute(loc);
    final isAnyTab = _isTabRoute(loc);
    final routeIdx = _indexFor(loc);
    final activeTab = isVisibleTab ? ref.watch(tabControllerModelProvider) : routeIdx;
    final navNotifier = ref.read(tabControllerModelProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isVisibleTab && ref.read(tabControllerModelProvider) != routeIdx) {
        navNotifier.jumpTo(routeIdx);
      }
    });

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final indicator = isDark
        ? AppColors.brandAccent.withValues(alpha: 0.18)
        : cs.primary.withValues(alpha: 0.12);
    final selectedIcon = isDark
        ? AppColors.brandAccent
        : cs.primary;
    final unselectedIcon = cs.onSurfaceVariant;
    final labelColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final selection = ref.watch(chatsTabSelectionControllerProvider);

    PreferredSizeWidget? appBar;
    if (isVisibleTab) {
      appBar = _buildAppBar(context, ref, activeTab);
    } else if (loc.startsWith('/updates')) {
      appBar = SearchableSelectableAppBar(
        title: 'Updates',
        searchHint: 'Search updates',
        normalActions: (startSearch) => [
          IconButton(onPressed: startSearch, icon: const Icon(Icons.search)),
          const TabMenu(kind: TabKind.updates),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      body: isVisibleTab
          ? PageView(
              controller: navNotifier.pageController,
              onPageChanged: (i) {
                navNotifier.onPageChanged(i);
                ref.read(searchBarControllerProvider.notifier).stop();
                ref.read(chatsTabSelectionControllerProvider.notifier).clear();
                final path = _tabRoots[i];
                final now = GoRouterState.of(context).uri.toString();
                if (!now.startsWith(path)) {
                  context.go(path);
                }
              },
              children: BottomNavigationConfig.visibleItems
                  .map((item) => _KeepAliveTab(child: item.buildScreen()))
                  .toList(),
            )
          : child,
      floatingActionButton: (isVisibleTab && activeTab == 0 && selection.isEmpty)
          ? FloatingActionButton(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.chat, size: 24),
              onPressed: () => GoRouter.of(context).push('/contacts'),
            )
          : null,
      bottomNavigationBar: isAnyTab
          ? Builder(
        builder: (_) {
          final chatsState = ref.watch(chatsTabControllerProvider);
          final count = chatsState.totalUnread;
          final visibleItems = BottomNavigationConfig.visibleItems;
          final clampedActiveTab = activeTab.clamp(0, visibleItems.length - 1);

          return NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              indicatorColor: indicator,
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final sel = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: sel ? selectedIcon : unselectedIcon,
                );
              }),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(color: labelColor, fontSize: 12),
              ),
            ),
            child: NavigationBar(
              selectedIndex: clampedActiveTab,
              onDestinationSelected: (i) {
                ref.read(tabControllerModelProvider.notifier).jumpTo(i);
                ref.read(searchBarControllerProvider.notifier).stop();
                ref.read(chatsTabSelectionControllerProvider.notifier).clear();
                context.go(_tabRoots[i]);
              },
              destinations: visibleItems.map((item) {
                switch (item) {
                  case NavigationTabItem.chats:
                    return NavigationDestination(
                      icon: ChatsBadgeIcon(
                        count: count,
                        icon: const Icon(Icons.chat_bubble_outline),
                      ),
                      selectedIcon: ChatsBadgeIcon(
                        count: count,
                        icon: const Icon(Icons.chat_bubble),
                      ),
                      label: 'Chats',
                    );
                  case NavigationTabItem.updates:
                    return const NavigationDestination(
                      icon: SmallDotBadgeIcon(
                        show: false,
                        child: Icon(Icons.update_outlined),
                      ),
                      selectedIcon: Icon(Icons.update),
                      label: 'Updates',
                    );
                  case NavigationTabItem.communities:
                    return const NavigationDestination(
                      icon: SmallDotBadgeIcon(
                        show: false,
                        child: Icon(Icons.groups_outlined),
                      ),
                      selectedIcon: Icon(Icons.groups),
                      label: 'Communities',
                    );
                  case NavigationTabItem.calls:
                    return const NavigationDestination(
                      icon: SmallDotBadgeIcon(
                        show: false,
                        child: Icon(Icons.call_outlined),
                      ),
                      selectedIcon: Icon(Icons.call),
                      label: 'Calls',
                    );
                }
              }).toList(),
            ),
          );
        },
      )
    : null,
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
