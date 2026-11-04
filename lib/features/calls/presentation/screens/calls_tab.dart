// lib/features/calls/presentation/screens/calls_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/calls/domain/services/call_participant_resolver.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/calls/presentation/widgets/call_history_tile.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_app_bar_actions.dart';

/// Application call history tab backed by Supabase `public.calls`.
class CallsTab extends ConsumerWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callsTabNotifierProvider);
    final cs = Theme.of(context).colorScheme;

    Widget body;

    if (state.isLoading && state.calls.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.errorMessage != null && state.calls.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(callsTabNotifierProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (state.calls.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.call_end_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'No calls yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Calls you make or receive will appear here',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    } else {
      final currentUid = SupabaseConfig.currentUserId ?? '';
      final contacts =
          ref.watch(contactsDataControllerProvider).cachedMatched;

      body = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 200) {
            ref.read(callsTabNotifierProvider.notifier).loadOlder();
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(callsTabNotifierProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: state.calls.length + (state.isLoadingMore ? 1 : 0),
            separatorBuilder: (_, index) {
              if (index >= state.calls.length - 1 && state.isLoadingMore) {
                return const SizedBox.shrink();
              }
              return const Divider(height: 1, indent: 72);
            },
            itemBuilder: (context, index) {
              if (index == state.calls.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final call = state.calls[index];
              final otherUid = CallParticipantResolver.resolveParticipantId(
                call: call,
                currentUserId: currentUid,
              );
              final peerName = CallParticipantResolver.resolveParticipantName(
                call: call,
                currentUserId: currentUid,
                contacts: contacts,
              );

              return CallHistoryTile(
                call: call,
                currentUserId: currentUid,
                resolvedPeerName: peerName,
                onCallBack: () {
                  ChatAppBarActions.initiateCall(
                    context,
                    ref,
                    call.chatId,
                    otherUid,
                    peerName,
                    call.callType,
                  );
                },
                onTap: () {
                  if (call.chatId.isNotEmpty) {
                    context.push(
                      '/chats/chat/${call.chatId}',
                      extra: {
                        'currentUserId': currentUid,
                        'otherUserId': otherUid,
                        'contactName': peerName,
                        'contactAvatar': call.peerAvatarUrl ?? '',
                      },
                    );
                  }
                },
              );
            },
          ),
        ),
      );
    }

    if (Scaffold.maybeOf(context) != null) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: body,
    );
  }
}
