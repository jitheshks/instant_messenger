import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/controller/chats_tab_controller.dart';
import 'package:provider/provider.dart';

import 'chats_badge_icon.dart';
import 'small_dot_badge_icon.dart';
import '../models/tab_controller_model.dart';
import '../view/screens/chats_tab_screen.dart';
import '../view/screens/updates_tab.dart';
import '../view/screens/communities_tab.dart';
import '../view/screens/calls_tab.dart';

class TabScaffold extends StatelessWidget {
  final Widget child; // ShellRoute’s active child route
  const TabScaffold({required this.child, super.key});

  static const List<String> _tabRoots = TabControllerModel.tabs; // ['/chats','/updates','/communities','/calls']

  bool _isTabRoute(String loc) {
    for (final t in _tabRoots) {
      if (loc.startsWith(t)) return true;
    }
    return false;
  }

  int _indexFor(String loc) {
    for (var i = 0; i < _tabRoots.length; i++) {
      if (loc.startsWith(_tabRoots[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Use the current router location (more reliable than matchedLocation for sibling routes)
    final state = GoRouterState.of(context);
  final loc = state.uri.toString(); // current path like '/contacts'
  final isTab = _isTabRoute(loc);
  final routeIdx = _indexFor(loc);

    // keep TabControllerModel in sync with route
    final model = context.read<TabControllerModel>();
    if (model.index != routeIdx) {
      model.jumpTo(routeIdx);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const darkGreen = Color(0xFF075E54);
    const lightGreen = Color(0xFFDCF8C6);

    final indicator = isDark ? lightGreen.withOpacity(0.20) : lightGreen;
    final selectedIcon = isDark ? Colors.white.withOpacity(0.92) : darkGreen;
    final unselectedIcon = isDark ? Colors.white.withOpacity(0.70) : const Color(0xFF1F1F1F);
    final labelColor = isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF1F1F1F);

    return Scaffold(
      // If we’re on a tab route, show the PageView of tabs.
      // Otherwise, render the ShellRoute child (e.g., /contacts).
      body: isTab
          ? PageView(
              controller: model.pageController,
              onPageChanged: (i) {
                model.onPageChanged(i);
                final path = _tabRoots[i];
              final now = GoRouterState.of(context).uri.toString();
              if (!now.startsWith(path)) {
                context.go(path);
              }
              },
              children: const [
                ChatsTabScreen(),
                UpdatesTab(),
                CommunitiesTab(),
                CallsTab(),
              ],
            )
          : child,

      bottomNavigationBar: Builder(
        builder: (_) {
          final idx = context.watch<TabControllerModel>().index;
          return NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              indicatorColor: indicator,
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final sel = states.contains(WidgetState.selected);
                return IconThemeData(color: sel ? selectedIcon : unselectedIcon);
              }),
              labelTextStyle: WidgetStatePropertyAll(TextStyle(color: labelColor, fontSize: 12)),
            ),
            child: NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) {
                context.read<TabControllerModel>().jumpTo(i);
                context.go(_tabRoots[i]);
              },
              destinations:  [

NavigationDestination(
  icon: Consumer<ChatsTabController?>(
    builder: (context, chatsCtrl, _) {
      if (chatsCtrl == null) {
        return const Icon(Icons.chat_bubble_outline);
      }

      final count = chatsCtrl.totalUnread;

      return ChatsBadgeIcon(
        count: count,
        icon: const Icon(Icons.chat_bubble_outline),
      );
    },
  ),
  selectedIcon: Consumer<ChatsTabController?>(
    builder: (context, chatsCtrl, _) {
      if (chatsCtrl == null) {
        return const Icon(Icons.chat_bubble);
      }

      final count = chatsCtrl.totalUnread;

      return ChatsBadgeIcon(
        count: count,
        icon: const Icon(Icons.chat_bubble),
      );
    },
  ),
  label: 'Chats',
),




                NavigationDestination(
                  icon: SmallDotBadgeIcon(show: false, child: Icon(Icons.update_outlined)),
                  selectedIcon: Icon(Icons.update),
                  label: 'Updates',
                ),
                NavigationDestination(
                  icon: SmallDotBadgeIcon(show: false, child: Icon(Icons.groups_outlined)),
                  selectedIcon: Icon(Icons.groups),
                  label: 'Communities',
                ),
                NavigationDestination(
                  icon: SmallDotBadgeIcon(show: false, child: Icon(Icons.call_outlined)),
                  selectedIcon: Icon(Icons.call),
                  label: 'Calls',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
