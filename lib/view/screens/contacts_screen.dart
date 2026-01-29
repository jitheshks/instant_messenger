import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:instant_messenger/controller/contacts_screen_controller.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:instant_messenger/utils/chat_route.dart'; // <- shared openChat
import 'package:instant_messenger/services/chat_id_service.dart';
import 'package:instant_messenger/controller/contacts_data_controller.dart';
import 'package:instant_messenger/controller/search_bar_controller.dart';
import 'package:instant_messenger/models/contact_list_entry.dart';
import 'package:instant_messenger/widgets/searchable_selectable_app_bar.dart';
import 'package:instant_messenger/widgets/tab_menu.dart';
import 'package:instant_messenger/widgets/header_tile.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchBarController(),
      child: const _ContactsBody(),
    );
  }
}

class _ContactsBody extends StatelessWidget {
  const _ContactsBody();

  @override
  Widget build(BuildContext context) {
    final data = context.read<ContactsDataController>();
    final searchCtrl = context.watch<SearchBarController>();
      final contactsCtrl = context.read<ContactsScreenController>(); // NEW
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SearchableSelectableAppBar(
        title: 'Select contact',
        searchHint: 'Search contacts',
        normalActions: (startSearch) => [
          IconButton(icon: const Icon(Icons.search), onPressed: startSearch),
          const TabMenu(kind: TabKind.contacts),

          if (kDebugMode)
  IconButton(
    icon: const Icon(Icons.bug_report_outlined),
    tooltip: 'Debug device contacts',
    onPressed: () async {
      await contactsCtrl.triggerDebugFetchAndNotify(limit: 20);

      if (!context.mounted) return; // ⬅️ guard after async

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debug contacts executed – check logs'),
        ),
      );
    },
  ),

        ],


      ),
      body: StreamBuilder<List<ContactListEntry>>(
        stream: data.watchMatched(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            if (kDebugMode) {
              debugPrint('[Contacts] stream error: ${snapshot.error}');
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Contacts error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }

          var contacts = snapshot.data ?? const <ContactListEntry>[];

          // Filter by search
          if (searchCtrl.query.isNotEmpty) {
            final q = searchCtrl.query.toLowerCase();
            contacts = contacts.where((e) {
              final name = e.displayName.toLowerCase();
              final about = (e.bio ?? '').toLowerCase();
              final phone = (e.phoneE164 ?? '').toLowerCase();
              return name.contains(q) || about.contains(q) || phone.contains(q);
            }).toList();
          }

          final children = <Widget>[
            _Tile(icon: Icons.group, title: 'New group', onTap: () {}),
            _Tile(icon: Icons.person_add, title: 'New contact', onTap: () {}),
            _Tile(icon: Icons.groups, title: 'New community', onTap: () {}),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 0, 4),
              child: Text(
                'Contacts on Messenger',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ];

          if (contacts.isEmpty) {
            children.add(
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No matched contacts yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            );
          } else {
   children.addAll(
  contacts.map(
    (p) => HeaderTile(
      key: ValueKey('${p.uid}_${p.avatarUrl}'),
      displayName: p.displayName,
      bio: p.bio ?? "",
      avatarUrl: p.avatarUrl,
      useListTile: true,
      radius: 24,
      // Add selection support later if using selection mode!
      onTap: () async {
        final me = FirebaseAuth.instance.currentUser?.uid ?? '';
        if (me.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not signed in')),
          );
          return;
        }
        if (p.uid == null || p.uid!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Contact not on Messenger: ${p.displayName}'),
            ),
          );
          return;
        }
        final chatId = ChatIdService.oneToOne(me, p.uid!);
        if (kDebugMode) {
          debugPrint(
            '[Contacts] Open chat with ${p.displayName} ($chatId)',
          );
        }
        await openChat(
otherUserId: p.uid!,
          context,
          chatId: chatId,
          currentUserId: me,
          contactName: p.displayName,
          contactAvatar: p.avatarUrl ?? '',
        );
      },
    ),
  ),
);

          }

          return ListView(children: children);
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  const _Tile({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title),
      onTap: onTap,
    );
  }
}
