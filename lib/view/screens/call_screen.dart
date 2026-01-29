import 'package:flutter/material.dart';

class CallScreen extends StatelessWidget {
  final String callID;
  final String userID;
  final String userName;

  // Keep constructor SAME so routes don’t break
  const CallScreen({
    super.key,
    required this.callID,
    required this.userID,
    required this.userName,
    Object? config, // ⛔ dummy param (ignored)
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call'),
      ),
      body: const Center(
        child: Text(
          '📞 Calls are temporarily disabled',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
