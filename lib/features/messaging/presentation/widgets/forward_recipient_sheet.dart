import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

/// Represents a candidate recipient for message forwarding.
class ForwardRecipientTarget {
  final String key;
  final String? chatId;
  final String otherUserId;
  final String title;
  final String subtitle;
  final String? avatarUrl;

  const ForwardRecipientTarget({
    required this.key,
    this.chatId,
    required this.otherUserId,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
  });
}

/// Modal sheet for selecting destination recipients (recent chats or contacts)
/// and forwarding one or more messages to them.
class ForwardRecipientSheet extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;

  const ForwardRecipientSheet({
    super.key,
    required this.messages,
  });

  @override
  ConsumerState<ForwardRecipientSheet> createState() =>
      _ForwardRecipientSheetState();
}

class _ForwardRecipientSheetState extends ConsumerState<ForwardRecipientSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedKeys = {};
  bool _isForwarding = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ForwardRecipientTarget> _buildTargets() {
    final chatsState = ref.watch(chatsTabControllerProvider);
    final contactsState = ref.watch(contactsDataControllerProvider);
    final currentUid = ref.watch(currentUserIdProvider) ??
        SupabaseConfig.currentUserId ??
        '';

    final targets = <ForwardRecipientTarget>[];
    final seenUserIds = <String>{};

    // 1. Add Recent Chats
    for (final chat in chatsState.chats) {
      if (chat.otherUserId.isEmpty) continue;
      seenUserIds.add(chat.otherUserId);

      // Resolve display name using contacts cache
      String displayName = chat.otherPhoneE164 ?? chat.otherUserId;
      for (final contact in contactsState.cachedMatched) {
        if (contact.uid == chat.otherUserId ||
            (contact.phoneE164 != null &&
                contact.phoneE164 == chat.otherPhoneE164)) {
          displayName = contact.displayName;
          break;
        }
      }

      targets.add(
        ForwardRecipientTarget(
          key: 'chat_${chat.id}',
          chatId: chat.id,
          otherUserId: chat.otherUserId,
          title: displayName,
          subtitle: chat.lastMessage.isNotEmpty
              ? chat.lastMessage
              : (chat.otherPhoneE164 ?? ''),
          avatarUrl: chat.avatarUrl,
        ),
      );
    }

    // 2. Add Contacts (excluding contacts that already appear in recent chats)
    for (final contact in contactsState.cachedMatched) {
      final uid = contact.uid;
      if (uid == null || uid.isEmpty || uid == currentUid) continue;
      if (seenUserIds.contains(uid)) continue;
      seenUserIds.add(uid);

      targets.add(
        ForwardRecipientTarget(
          key: 'contact_$uid',
          chatId: null,
          otherUserId: uid,
          title: contact.displayName,
          subtitle: contact.phoneE164 ?? contact.bio ?? '',
          avatarUrl: contact.avatarUrl,
        ),
      );
    }

    // 3. Filter by search query if non-empty
    if (_searchQuery.isEmpty) {
      return targets;
    }

    return targets.where((t) {
      return t.title.toLowerCase().contains(_searchQuery) ||
          t.subtitle.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Future<void> _forwardMessages(List<ForwardRecipientTarget> allTargets) async {
    if (_isForwarding || _selectedKeys.isEmpty) return;

    setState(() {
      _isForwarding = true;
    });

    final messagesRepo = ref.read(messagesRepositoryProvider);
    final outboxService = ref.read(outboxServiceProvider);
    final currentUid = ref.read(currentUserIdProvider) ??
        SupabaseConfig.currentUserId ??
        '';

    if (messagesRepo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Repository unavailable')),
        );
        setState(() => _isForwarding = false);
      }
      return;
    }

    final selectedTargets =
        allTargets.where((t) => _selectedKeys.contains(t.key)).toList();

    try {
      for (final target in selectedTargets) {
        String? destinationChatId = target.chatId;

        // Resolve or create direct chat if not already existing
        if (destinationChatId == null || destinationChatId.isEmpty) {
          destinationChatId =
              await messagesRepo.getOrCreateDirectChat(target.otherUserId);
        }

        if (destinationChatId == null || destinationChatId.isEmpty) {
          continue;
        }

        for (final original in widget.messages) {
          final newMsgId = const Uuid().v4();

          if (original.type == MessageType.media && original.media != null) {
            final mediaUrl = original.media!.url;
            final isLocal = mediaUrl.startsWith('/');
            final localExists = isLocal && File(mediaUrl).existsSync();

            if (isLocal && !localExists) {
              debugPrint(
                '[ForwardRecipientSheet] Media file missing on device: $mediaUrl',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Media file is unavailable on this device'),
                  ),
                );
              }
              continue;
            }

            if (localExists && outboxService != null) {
              final forwardedMediaMsg = ChatMessage(
                id: newMsgId,
                chatId: destinationChatId,
                senderId: currentUid,
                text: original.text,
                sentAt: DateTime.now().toUtc(),
                deliveryState: DeliveryState.sending,
                type: MessageType.media,
                uploadProgress: 0.0,
                failure: null,
                isForwarded: true,
                media: original.media,
              );
              await outboxService.savePending(forwardedMediaMsg);
            } else {
              final forwardedMsg = ChatMessage(
                id: newMsgId,
                chatId: destinationChatId,
                senderId: currentUid,
                text: original.text,
                sentAt: DateTime.now().toUtc(),
                deliveryState: DeliveryState.sending,
                type: MessageType.media,
                media: original.media,
                isForwarded: true,
              );
              await messagesRepo.sendMessage(
                destinationChatId,
                forwardedMsg,
                otherUserId: target.otherUserId,
                otherName: target.title,
                otherAvatar: target.avatarUrl,
              );
            }
          } else {
            final forwardedMsg = ChatMessage(
              id: newMsgId,
              chatId: destinationChatId,
              senderId: currentUid,
              text: original.text,
              sentAt: DateTime.now().toUtc(),
              deliveryState: DeliveryState.sending,
              type: original.type,
              media: original.media,
              isForwarded: true,
            );
            await messagesRepo.sendMessage(
              destinationChatId,
              forwardedMsg,
              otherUserId: target.otherUserId,
              otherName: target.title,
              otherAvatar: target.avatarUrl,
            );
          }
        }

        // Successfully delivered to this target: remove from selection to avoid duplicate on partial retry
        _selectedKeys.remove(target.key);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('[ForwardRecipientSheet] Error forwarding messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to forward messages: $e')),
        );
        setState(() => _isForwarding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final targets = _buildTargets();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Forward to...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (_selectedKeys.isNotEmpty)
                  Text(
                    '${_selectedKeys.length} selected',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats or contacts',
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const Divider(height: 12),

          // Recipients List
          Expanded(
            child: targets.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'No matching recipients'
                          : 'No recent chats or contacts',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: targets.length,
                    itemBuilder: (context, index) {
                      final target = targets[index];
                      final isSelected = _selectedKeys.contains(target.key);

                      return ListTile(
                        leading: SafeAvatar(
                          fallbackName: target.title,
                          avatarUrl: target.avatarUrl,
                          radius: 22,
                        ),
                        title: Text(
                          target.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          target.subtitle,
                          style: TextStyle(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: cs.primary,
                          onChanged: _isForwarding
                              ? null
                              : (_) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedKeys.remove(target.key);
                                    } else {
                                      _selectedKeys.add(target.key);
                                    }
                                  });
                                },
                        ),
                        onTap: _isForwarding
                            ? null
                            : () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedKeys.remove(target.key);
                                  } else {
                                    _selectedKeys.add(target.key);
                                  }
                                });
                              },
                      );
                    },
                  ),
          ),

          // Bottom Action Bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_selectedKeys.isEmpty || _isForwarding)
                      ? null
                      : () => _forwardMessages(targets),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: _isForwarding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isForwarding
                        ? 'Forwarding...'
                        : 'Forward (${_selectedKeys.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
