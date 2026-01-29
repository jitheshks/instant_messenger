// lib/widgets/tab_menu.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum TabKind { chats, updates, calls, communities, contacts }

class TabMenu extends StatelessWidget {
  const TabMenu({super.key, required this.kind});
  final TabKind kind;

  @override
  Widget build(BuildContext context) {
    // Define menu tuples as (value, icon, label).
    // For contacts, use icon == null to render text-only items.
    final items = switch (kind) {
      TabKind.chats => const [
        (1, Icons.group_outlined, 'New group'),
        (2, Icons.star_border, 'Starred'),
        (99, Icons.settings_outlined, 'Settings'),
      ],
      TabKind.updates => const [
        (1, Icons.broadcast_on_personal_outlined, 'Create Channel'),
        (2, Icons.lock_outline, 'Status Privacy'),
        (3, Icons.star_border_rounded, 'Starred'),
        (99, Icons.settings_outlined, 'Settings'),
      ],
      TabKind.calls => const [
        (1, Icons.delete_outline, 'Clear call log'),
        (99, Icons.settings_outlined, 'Settings'),
      ],
      TabKind.communities => const [
        (99, Icons.settings_outlined, 'Settings'),
      ],
      TabKind.contacts => const [
        (10, null, 'Invite a friend'),
        (11, null, 'Contacts'),
        (12, null, 'Refresh'),
        (13, null, 'Help'),
        (99, null, 'Settings'),
      ],
    };

    return PopupMenuButton<int>(
      offset: const Offset(0, kToolbarHeight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final t in items)
          t.$2 == null
              ? buildTextItem(t.$1, t.$3)
              : buildIconItem(t.$1, t.$2 as IconData, t.$3),
      ],
      onSelected: (value) async {
        if (value == 99) {
          context.push('/settings');
          return;
        }
        if (kind == TabKind.contacts) {
          switch (value) {
            case 10:
              // TODO: share invite link/text
              break;
            case 11:
              // TODO: open device contacts app or permissions/settings
              break;
            case 12:
              // TODO: trigger manual refresh if repository supports it
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing contacts...')),
              );
              break;
            case 13:
              // TODO: show help page or dialog
              break;
          }
          return;
        }
        // Handle other tab-specific actions here if needed
      },
    );
  }
}

// With icon
PopupMenuItem<int> buildIconItem(int value, IconData icon, String label) {
  return PopupMenuItem<int>(
    value: value,
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      contentPadding: EdgeInsets.zero,
      horizontalTitleGap: 16,
      dense: true,
    ),
  );
}

// Text-only
PopupMenuItem<int> buildTextItem(int value, String label) {
  return PopupMenuItem<int>(
    value: value,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(label),
    ),
  );
}
