import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:instant_messenger/controller/search_bar_controller.dart';

typedef NormalActionsBuilder = List<Widget> Function(VoidCallback startSearch);
typedef SelectionActionsBuilder = List<Widget> Function();

class SearchableSelectableAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  // Normal mode
  final String title;
  final NormalActionsBuilder normalActions;

  // Search mode (uses SearchBarController from Provider)
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
  Widget build(BuildContext context) {
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

    final c = context.watch<SearchBarController?>();
    if (c?.searching == true) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.read<SearchBarController>().stop,
        ),
        title: TextField(
          controller: c!.text,
          autofocus: true,
          decoration: InputDecoration(
            hintText: searchHint,
            border: InputBorder.none,
          ),
          onChanged: context.read<SearchBarController>().onChanged,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (c.query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                final cc = context.read<SearchBarController>();
                cc.text.clear();
                cc.onChanged('');
              },
            ),
        ],
      );
    }

    return AppBar(
      elevation: 0,
      title: Text(title),
      actions: normalActions(
        context.read<SearchBarController?>()?.start ?? () {},
      ),
    );
  }
}
