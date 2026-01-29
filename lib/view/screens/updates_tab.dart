import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controller/search_bar_controller.dart';
import '../../widgets/searchable_selectable_app_bar.dart';
import '../../widgets/tab_menu.dart';

class UpdatesTab extends StatelessWidget {
  const UpdatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchBarController(),
      child: Scaffold(
        appBar: SearchableSelectableAppBar(
          title: 'Updates',
          searchHint: 'Search updates',
          normalActions: (startSearch) => [
            IconButton(onPressed: startSearch, icon: const Icon(Icons.search)),
            const TabMenu(kind: TabKind.updates),
          ],
        ),
        body: const Center(child: Text('Updates (dummy)')),
      ),
    );
  }
}
