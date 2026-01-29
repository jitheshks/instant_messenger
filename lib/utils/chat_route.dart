// lib/utils/chat_route.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Centralized chat navigation helper
/// Router knows ONLY chatId + UI metadata
/// Peer user is derived inside ChatScreenController
Future<void> openChat(
  BuildContext context, {
  required String chatId,
  required String currentUserId,
    required String otherUserId,
  required String contactName,
  required String contactAvatar,
}) async {
  if (chatId.isEmpty || currentUserId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat not ready yet')),
    );
    return;
  }

  GoRouter.of(context).push(
    '/chats/chat/$chatId',
    extra: {
      'currentUserId': currentUserId,
       'otherUserId': otherUserId,
      'contactName': contactName,
      'contactAvatar': contactAvatar,
    },
  );
}
