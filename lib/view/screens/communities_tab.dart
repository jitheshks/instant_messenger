import 'package:flutter/material.dart';
import '../../widgets/tab_menu.dart';

class CommunitiesTab extends StatelessWidget {
  const CommunitiesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text('Communities'),
  actions: const [TabMenu(kind: TabKind.communities)],
),
      body: const Center(child: Text('Communities (dummy)')),
    );
  }
}
