// lib/shared/utils/chat_route.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';

/// Centralized chat navigation helper.
///
/// Guarantees that only valid RFC 4122 UUID chat identifiers are pushed to GoRouter.
/// If a non-UUID identifier is received (legacy string fallback), transparently resolves
/// the direct chat UUID via `get_or_create_direct_chat` RPC before navigation.
Future<void> openChat(
  BuildContext context, {
  required String chatId,
  required String currentUserId,
  String otherUserId = '',
  required String contactName,
  required String contactAvatar,
  bool isGroup = false,
}) async {
  if (currentUserId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Authentication required')));
    }
    return;
  }

  String resolvedChatId = chatId.trim();
  final uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  // Fallback: If chatId is not a valid UUID, attempt resolution via RPC using peer ID
  if (!uuidRegex.hasMatch(resolvedChatId) && !isGroup && otherUserId.trim().isNotEmpty) {
    try {
      final directChatId = await SupabaseConfig.client.rpc(
        'get_or_create_direct_chat',
        params: {'p_peer_id': otherUserId.trim()},
      );
      if (directChatId != null &&
          uuidRegex.hasMatch(directChatId.toString())) {
        resolvedChatId = directChatId.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatRoute] Failed to resolve direct chat UUID: $e');
      }
    }
  }

  if (!uuidRegex.hasMatch(resolvedChatId)) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid chat identifier')));
    }
    return;
  }

  if (!context.mounted) return;

  GoRouter.of(context).push(
    '/chats/chat/$resolvedChatId',
    extra: {
      'currentUserId': currentUserId,
      'otherUserId': isGroup ? '' : otherUserId,
      'contactName': contactName,
      'contactAvatar': contactAvatar,
      'isGroup': isGroup,
    },
  );
}
