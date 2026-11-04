import 'package:flutter/material.dart';

class UpdatesTab extends StatelessWidget {
  const UpdatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    const body = Center(child: Text('Updates (dummy)'));
    if (Scaffold.maybeOf(context) != null) {
      return body;
    }
    return const Scaffold(body: body);
  }
}
