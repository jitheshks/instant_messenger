// lib/app/navigation/navigation_config.dart

import 'package:flutter/material.dart';
import 'package:instant_messenger/features/calls/presentation/screens/calls_tab.dart';
import 'package:instant_messenger/features/chats/presentation/screens/chats_tab_screen.dart';
import 'package:instant_messenger/features/chats/presentation/screens/communities_tab.dart';
import 'package:instant_messenger/features/chats/presentation/screens/updates_tab.dart';

/// Supported tabs in the top-level messenger shell.
enum NavigationTabItem {
  chats(
    path: '/chats',
    label: 'Chats',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
  ),
  updates(
    path: '/updates',
    label: 'Updates',
    icon: Icons.update_outlined,
    selectedIcon: Icons.update,
  ),
  communities(
    path: '/communities',
    label: 'Communities',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  calls(
    path: '/calls',
    label: 'Calls',
    icon: Icons.call_outlined,
    selectedIcon: Icons.call,
  );

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavigationTabItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Instantiates the tab page view content widget.
  Widget buildScreen() {
    switch (this) {
      case NavigationTabItem.chats:
        return const ChatsTabScreen();
      case NavigationTabItem.updates:
        return const UpdatesTab();
      case NavigationTabItem.communities:
        return const CommunitiesTab();
      case NavigationTabItem.calls:
        return const CallsTab();
    }
  }
}

/// Central configuration for bottom navigation visibility, indexing, and feature toggles.
class BottomNavigationConfig {
  const BottomNavigationConfig._();

  /// Temporarily hide the Updates (Status/Stories) tab from the visible bottom navigation bar.
  /// Set to `false` until Status/Stories feature implementation is complete and ready for release.
  /// NOTE: The underlying Updates feature implementation (screens, routes, models) remains fully preserved.
  static const bool isUpdatesTabVisible = false;

  /// Ordered list of tabs currently active and visible in the bottom navigation.
  static List<NavigationTabItem> get visibleItems => [
        NavigationTabItem.chats,
        if (isUpdatesTabVisible) NavigationTabItem.updates,
        NavigationTabItem.communities,
        NavigationTabItem.calls,
      ];

  /// Ordered list of route paths for visible tabs.
  static List<String> get visiblePaths =>
      visibleItems.map((item) => item.path).toList();

  /// Maps a URI location to the corresponding visible tab index.
  /// If the URI points to a hidden tab (e.g. direct deep link to /updates),
  /// defaults safely without index out of bounds.
  static int indexForLocation(String loc) {
    final paths = visiblePaths;
    for (var i = 0; i < paths.length; i++) {
      if (loc.startsWith(paths[i])) return i;
    }
    return 0;
  }

  /// Checks if a route path belongs to any shell tab (visible or preserved).
  static bool isTabRoute(String loc) {
    for (final item in NavigationTabItem.values) {
      if (loc.startsWith(item.path)) return true;
    }
    return false;
  }

  /// Checks if a route path belongs to a currently visible shell tab.
  static bool isVisibleTabRoute(String loc) {
    for (final path in visiblePaths) {
      if (loc.startsWith(path)) return true;
    }
    return false;
  }
}
