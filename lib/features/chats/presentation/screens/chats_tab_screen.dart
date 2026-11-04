import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/chat_list_item.dart';
import 'package:instant_messenger/shared/widgets/states/empty_state_view.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';

class ChatsTabScreen extends ConsumerWidget {
  const ChatsTabScreen({super.key});

  String resolveDisplayName(WidgetRef ref, ChatSummary chat) {
    if (chat.isGroup && chat.title != null && chat.title!.isNotEmpty) {
      return chat.title!;
    }
    final contacts = ref.watch(contactsDataControllerProvider);
    return ContactIdentityResolver.resolveIdentity(
      phoneE164: chat.otherPhoneE164,
      userId: chat.otherUserId,
      contacts: contacts.cachedMatched,
      fallback: (chat.otherPhoneE164 != null && chat.otherPhoneE164!.isNotEmpty)
          ? chat.otherPhoneE164!
          : ((chat.otherUserId.isNotEmpty) ? chat.otherUserId : 'Chat'),
    );
  }

  String deriveOtherUserId(ChatSummary chat) {
    final currentUid = SupabaseConfig.currentUserId ?? '';
    if (chat.members.length == 2) {
      return chat.members.firstWhere((m) => m != currentUid, orElse: () => '');
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid =
        ref.watch(currentUserIdProvider) ?? SupabaseConfig.currentUserId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (uid.isNotEmpty) {
        ref.read(chatsTabControllerProvider.notifier).ensureBound(uid);
      }
    });
    debugPrint('🟢 BUILD → ChatsTabScreen (uid=$uid)');
    final chatsState = ref.watch(chatsTabControllerProvider);
    final chatsNotifier = ref.read(chatsTabControllerProvider.notifier);

    final selection = ref.watch(chatsTabSelectionControllerProvider);

    final body = Builder(
      builder: (context) {
        // 1️⃣ Initial loading: waiting for initial load and no cached data
        if (chatsState.isLoading &&
            chatsState.chats.isEmpty &&
            chatsState.errorMessage == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // 2️⃣ Error or Offline with NO cached conversations
        if (chatsState.chats.isEmpty && chatsState.errorMessage != null) {
          final isOffline = chatsState.isOffline;
          final isBackendUnavailable = chatsState.isBackendUnavailable;

          final emptyIcon = isOffline
              ? Icons.wifi_off_rounded
              : (isBackendUnavailable
                  ? Icons.cloud_off_rounded
                  : Icons.error_outline_rounded);

          final emptyTitle = isOffline
              ? "You're offline"
              : (isBackendUnavailable
                  ? "Connecting to messenger services..."
                  : 'Unable to load chats');

          final emptyMessage = isOffline
              ? (chatsState.errorMessage ??
                  "Please check your internet connection.")
              : (isBackendUnavailable
                  ? "Unable to reach messenger servers. Please tap retry to reconnect."
                  : chatsState.errorMessage);

          return RefreshIndicator(
            onRefresh: () => chatsNotifier.refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: EmptyStateView(
                  icon: emptyIcon,
                  title: emptyTitle,
                  message: emptyMessage,
                  actionLabel: 'Retry',
                  onAction: () => chatsNotifier.retry(),
                ),
              ),
            ),
          );
        }

        // 3️⃣ Loaded with NO conversations (empty valid state)
        if (chatsState.chats.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => chatsNotifier.refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: EmptyStateView(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No conversations yet',
                  message:
                      'Start a conversation with someone to see your messages here.',
                  actionLabel: 'Start a conversation',
                  onAction: () => GoRouter.of(context).push('/contacts'),
                ),
              ),
            ),
          );
        }

        // 4️⃣ Loaded WITH conversations (with optional offline/error or realtime banner)
        final hasErrorBanner = chatsState.errorMessage != null;
        final hasRealtimeBanner =
            !hasErrorBanner && chatsState.isRealtimeDisconnected;
        final hasBanner = hasErrorBanner || hasRealtimeBanner;

        return RefreshIndicator(
          onRefresh: () => chatsNotifier.refresh(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: chatsState.chats.length + (hasBanner ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasBanner && index == 0) {
                if (hasErrorBanner) {
                  final isOffline = chatsState.isOffline;
                  final isBackendUnavailable = chatsState.isBackendUnavailable;

                  final bannerIcon = isOffline
                      ? Icons.wifi_off_rounded
                      : (isBackendUnavailable
                          ? Icons.cloud_off_rounded
                          : Icons.warning_amber_rounded);

                  final bannerText = isOffline
                      ? "You are offline. Please check your internet connection."
                      : (isBackendUnavailable
                          ? "Connecting to messenger services..."
                          : chatsState.errorMessage!);

                  final bg = isBackendUnavailable
                      ? Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withValues(alpha: 0.5)
                      : Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.5);

                  final fg = isBackendUnavailable
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onErrorContainer;

                  return Container(
                    color: bg,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(bannerIcon, size: 18, color: fg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bannerText,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: fg),
                          ),
                        ),
                        TextButton(
                          onPressed: () => chatsNotifier.retry(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (hasRealtimeBanner) {
                  return Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Connecting to Realtime updates...',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              }

              final chatIndex = hasBanner ? index - 1 : index;
              final chat = chatsState.chats[chatIndex];
              final displayName = resolveDisplayName(ref, chat);
              final otherUserId = deriveOtherUserId(chat);

              return ChatListItem(
                key: ValueKey(chat.id),
                chat: chat,
                displayName: displayName,
                onTap: () {
                  if (otherUserId.isEmpty) {
                    debugPrint('❌ Missing otherUserId for chat=${chat.id}');
                    return;
                  }

                  context.push(
                    '/chats/chat/${chat.id}',
                    extra: {
                      'currentUserId': uid,
                      'otherUserId': otherUserId,
                      'contactName': displayName,
                      'contactAvatar': '',
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );

    // If already hosted inside a parent Scaffold (such as TabScaffold),
    // return body directly so the shared parent AppBar and FAB are used.
    if (Scaffold.maybeOf(context) != null) {
      return body;
    }

    // Standalone fallback (e.g. unit/widget tests)
    return Scaffold(
      body: body,
      floatingActionButton: selection.isNotEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.chat, size: 24),
              onPressed: () => GoRouter.of(context).push('/contacts'),
            ),
    );
  }
}
