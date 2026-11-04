import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';
import 'package:instant_messenger/shared/widgets/bars/search_bar_notifier.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';

import 'package:instant_messenger/shared/utils/chat_route.dart'; // <- shared openChat
import 'package:instant_messenger/shared/widgets/bars/searchable_selectable_app_bar.dart';
import 'package:instant_messenger/shared/widgets/menus/tab_menu.dart';
import 'package:instant_messenger/shared/widgets/tiles/header_tile.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ContactsBody();
  }
}

class _ContactsBody extends ConsumerStatefulWidget {
  const _ContactsBody();

  @override
  ConsumerState<_ContactsBody> createState() => _ContactsBodyState();
}

class _ContactsBodyState extends ConsumerState<_ContactsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(contactsDataControllerProvider.notifier).loadMatchedContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = ref.watch(contactsDataControllerProvider);
    final dataNotifier = ref.read(contactsDataControllerProvider.notifier);
    final searchCtrl = ref.watch(searchBarControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SearchableSelectableAppBar(
        title: 'Select contact',
        searchHint: 'Search contacts',
        normalActions: (startSearch) => [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh contacts',
            onPressed: contactsState.loading
                ? null
                : () => dataNotifier.loadMatchedContacts(force: true),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: startSearch),
          const TabMenu(kind: TabKind.contacts),

          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'Debug device contacts',
              onPressed: () async {
                await dataNotifier.triggerDebugFetchAndNotify(limit: 20);

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Debug contacts executed – check logs'),
                  ),
                );
              },
            ),
        ],
      ),
      body: _buildContent(contactsState, dataNotifier, searchCtrl, theme),
    );
  }

  Widget _buildContent(
    ContactsDataState contactsState,
    ContactsDataNotifier dataNotifier,
    SearchBarState searchCtrl,
    ThemeData theme,
  ) {
    // 1. Initial loading when cache is empty
    if (contactsState.loading && contactsState.cachedMatched.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Full error state when cache is empty
    if (contactsState.errorMessage != null &&
        contactsState.cachedMatched.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                contactsState.isRateLimited
                    ? Icons.hourglass_top_rounded
                    : Icons.error_outline_rounded,
                size: 54,
                color: contactsState.isRateLimited
                    ? Colors.amber.shade700
                    : Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                contactsState.isRateLimited
                    ? 'Sync Limit Reached'
                    : 'Unable to Load Contacts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                contactsState.errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (!contactsState.isRateLimited)
                ElevatedButton.icon(
                  onPressed: () =>
                      dataNotifier.loadMatchedContacts(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
            ],
          ),
        ),
      );
    }

    var contacts = contactsState.cachedMatched;

    // Filter by search query purely in-memory
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
      // Non-intrusive warning banner when contacts are available from cache
      if (contactsState.errorMessage != null)
        Builder(
          builder: (context) {
            final isDark = theme.brightness == Brightness.dark;
            final bannerBg = contactsState.isRateLimited
                ? (isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.25)
                    : Colors.amber.shade50)
                : (isDark
                    ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
                    : Colors.red.shade50);
            final bannerBorder = contactsState.isRateLimited
                ? (isDark ? Colors.amber.shade700 : Colors.amber.shade300)
                : (isDark
                    ? theme.colorScheme.error.withValues(alpha: 0.5)
                    : Colors.red.shade200);
            final bannerIconColor = contactsState.isRateLimited
                ? (isDark ? Colors.amber.shade300 : Colors.amber.shade800)
                : (isDark ? theme.colorScheme.error : Colors.red.shade800);
            final bannerTextColor = contactsState.isRateLimited
                ? (isDark ? Colors.amber.shade100 : Colors.amber.shade900)
                : (isDark
                    ? theme.colorScheme.onErrorContainer
                    : Colors.red.shade900);

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bannerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: bannerBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    contactsState.isRateLimited
                        ? Icons.info_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: bannerIconColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      contactsState.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: bannerTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              searchCtrl.query.isNotEmpty
                  ? 'No contacts matching "${searchCtrl.query}"'
                  : 'No matched contacts yet',
              style: const TextStyle(color: Colors.grey),
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
              final me = SupabaseConfig.currentUserId ?? '';
              if (me.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Not signed in')),
                );
                return;
              }
              if (p.uid == null || p.uid!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Contact not on Messenger: ${p.displayName}',
                    ),
                  ),
                );
                return;
              }
              try {
                final sb = SupabaseConfig.client;
                final directChatId = await sb.rpc(
                        'get_or_create_direct_chat',
                  params: {'p_peer_id': p.uid!},
                );
                if (!mounted) return;
                final chatId = directChatId?.toString() ?? '';
                if (chatId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not initialize direct chat'),
                    ),
                  );
                  return;
                }
                if (kDebugMode) {
                  debugPrint(
                    '[Contacts] Open direct chat with ${p.displayName} (UUID: $chatId)',
                  );
                }
                await openChat(
                  context,
                  chatId: chatId,
                  currentUserId: me,
                  otherUserId: p.uid!,
                  contactName: p.displayName,
                  contactAvatar: p.avatarUrl ?? '',
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to open chat: $e')),
                );
              }
            },
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => dataNotifier.loadMatchedContacts(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
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
