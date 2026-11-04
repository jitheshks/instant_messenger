import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';

/// AppBar call actions for ChatScreen supporting voice and video calls.
class ChatAppBarActions {
  static List<Widget> build(
    BuildContext context, {
    WidgetRef? ref,
    String? chatId,
    String? peerUserId,
    String? peerName,
  }) {
    final canCall = ref != null &&
        chatId != null &&
        chatId.isNotEmpty &&
        peerUserId != null &&
        peerUserId.isNotEmpty;

    return [
      IconButton(
        icon: const Icon(Icons.videocam_outlined),
        onPressed: canCall
            ? () => initiateCall(
                  context,
                  ref,
                  chatId,
                  peerUserId,
                  peerName ?? 'Contact',
                  CallType.video,
                )
            : () => _showUnavailable(context),
        tooltip: 'Video call',
      ),
      IconButton(
        icon: const Icon(Icons.call_outlined),
        onPressed: canCall
            ? () => initiateCall(
                  context,
                  ref,
                  chatId,
                  peerUserId,
                  peerName ?? 'Contact',
                  CallType.audio,
                )
            : () => _showUnavailable(context),
        tooltip: 'Voice call',
      ),
      const IconButton(icon: Icon(Icons.more_vert), onPressed: null),
    ];
  }

  static Future<void> initiateCall(
    BuildContext context,
    WidgetRef ref,
    String chatId,
    String peerUserId,
    String peerName,
    CallType callType,
  ) async {
    final callerName = LocalCache.displayName ?? 'Caller';
    final success = await ref
        .read(callControllerProvider.notifier)
        .startOutgoingCall(
          chatId: chatId,
          inviteeIds: [peerUserId],
          callType: callType,
          localUserName: callerName,
        );

    if (!context.mounted) return;

    final callId = ref.read(callControllerProvider).callId;

    if (success && callId != null && callId.isNotEmpty) {
      final encodedName = Uri.encodeComponent(peerName);
      context.push(
        '/call/$callId?userID=$peerUserId&userName=$encodedName&callType=${callType.name}&incoming=false',
      );
    } else {
      final errorMsg = ref.read(callControllerProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                'Could not start call. Please check permissions or network connection.',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Temporarily unavailable'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
