import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controller/search_bar_controller.dart';
import '../../widgets/searchable_selectable_app_bar.dart';
import '../../widgets/tab_menu.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchBarController(),
      child: Scaffold(
        appBar: SearchableSelectableAppBar(
          title: 'Calls',
          searchHint: 'Search calls',
          normalActions: (startSearch) => [
            IconButton(onPressed: startSearch, icon: const Icon(Icons.search)),
            const TabMenu(kind: TabKind.calls),
          ],
          // selectionMode/selectedCount optional here (no selection on calls list yet)
        ),
        body: const Center(child: Text('Calls (dummy)')),
      ),
    );
  }
}
