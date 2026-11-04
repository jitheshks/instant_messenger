import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/shared/widgets/bars/search_bar_notifier.dart';

typedef NormalActionsBuilder = List<Widget> Function(VoidCallback startSearch);
typedef SelectionActionsBuilder = List<Widget> Function();

class SearchableSelectableAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  // Normal mode
  final String title;
  final NormalActionsBuilder normalActions;

  // Search mode (uses SearchBarController from Riverpod)
  final String searchHint;

  // Selection mode
  final bool selectionMode;
  final int selectedCount;
  final VoidCallback? onCloseSelection;
  final VoidCallback? onSelectAll;
  final SelectionActionsBuilder? selectionActions;

  const SearchableSelectableAppBar({
    super.key,
    required this.title,
    required this.normalActions,
    this.searchHint = 'Search',
    this.selectionMode = false,
    this.selectedCount = 0,
    this.onCloseSelection,
    this.onSelectAll,
    this.selectionActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCloseSelection,
        ),
        title: Text('$selectedCount selected'),
        actions: [
          if (onSelectAll != null)
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: onSelectAll,
            ),
          ...?selectionActions?.call(),
        ],
      );
    }

    final searchState = ref.watch(searchBarControllerProvider);
    final searchNotifier = ref.read(searchBarControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    if (searchState.searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: searchNotifier.stop,
        ),
        title: TextField(
          controller: searchNotifier.text,
          autofocus: true,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
          ),
          cursorColor: cs.primary,
          decoration: InputDecoration(
            hintText: searchHint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 18,
            ),
            border: InputBorder.none,
          ),
          onChanged: searchNotifier.onChanged,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (searchState.query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                searchNotifier.text.clear();
                searchNotifier.onChanged('');
              },
            ),
        ],
      );
    }

    return AppBar(
      elevation: 0,
      title: Text(title),
      actions: normalActions(searchNotifier.start),
    );
  }
}
