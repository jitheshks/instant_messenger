import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/screens/chat_screen.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_route_observer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves missing conversation metadata (such as peerUserId and contact info)
/// when navigating to a chat from external notification intents, deep links,
/// or background taps where `state.extra` is absent or incomplete.
///
/// Enforces participant authorization: verifies that the current authenticated user
/// is an active member of the conversation before rendering [ChatScreen].
class ChatRouteResolver extends ConsumerStatefulWidget {
  final String chatId;
  final String currentUserId;
  final String initialContactName;
  final String initialContactAvatar;

  const ChatRouteResolver({
    super.key,
    required this.chatId,
    required this.currentUserId,
    this.initialContactName = 'Chat',
    this.initialContactAvatar = '',
  });

  @override
  ConsumerState<ChatRouteResolver> createState() => _ChatRouteResolverState();
}

class _ChatRouteResolverState extends ConsumerState<ChatRouteResolver> {
  bool _loading = true;
  bool _isGroup = false;
  String? _resolvedPeerId;
  String? _resolvedContactName;
  String? _resolvedContactAvatar;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolveConversation();
  }

  Future<void> _resolveConversation() async {
    debugPrint(
      '[NotificationTap] ChatRouteResolver: resolving conversation for chatId: ${widget.chatId}, currentUserId: ${widget.currentUserId}',
    );

    // 1. Try local cache first for instant, offline-capable resolution
    try {
      final chatsStore =
          HiveDatabaseManager.instance.activeDatabase?.chatsStore;
      if (chatsStore != null) {
        final summary = chatsStore.getChatSummary(widget.chatId);
        if (summary != null) {
          if (summary.isGroup) {
            if (mounted) {
              final groupTitle = (summary.title != null && summary.title!.isNotEmpty)
                  ? summary.title!
                  : widget.initialContactName;
              debugPrint(
                '[NotificationTap] ChatRouteResolver: resolved group from local Hive cache -> title: "$groupTitle"',
              );
              setState(() {
                _isGroup = true;
                _resolvedPeerId = '';
                _resolvedContactName = groupTitle;
                _resolvedContactAvatar =
                    summary.avatarUrl ?? widget.initialContactAvatar;
                _loading = false;
              });
              return;
            }
          } else if (summary.otherUserId.isNotEmpty) {
            if (mounted) {
              final contacts =
                  ref.read(contactsDataControllerProvider).cachedMatched;
              final resolvedName = ContactIdentityResolver.resolveIdentity(
                phoneE164: summary.otherPhoneE164,
                contacts: contacts,
                fallback: widget.initialContactName,
              );
              debugPrint(
                '[NotificationTap] ChatRouteResolver: resolved from local Hive cache -> peerId: ${summary.otherUserId}, contactName: "$resolvedName"',
              );
              setState(() {
                _isGroup = false;
                _resolvedPeerId = summary.otherUserId;
                _resolvedContactName = resolvedName;
                _resolvedContactAvatar =
                    summary.avatarUrl ?? widget.initialContactAvatar;
                _loading = false;
              });
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatRouteResolver] Local cache lookup note: $e');
    }

    // 2. Query Supabase chat_members and chats if not found in local cache
    try {
      final sb = Supabase.instance.client;

      final chatRow = await sb
          .from('chats')
          .select('id, type, title, avatar_url')
          .eq('id', widget.chatId)
          .maybeSingle();

      final rows = await sb
          .from('chat_members')
          .select(
              'user_id, role, profile:profiles(display_name, avatar_url, phone_e164)')
          .eq('chat_id', widget.chatId);

      final members = (rows as List).cast<Map<String, dynamic>>();
      if (members.isEmpty) {
        if (mounted) {
          debugPrint(
            '[NotificationTap] ❌ ChatRouteResolver: Conversation ${widget.chatId} not found in chat_members',
          );
          setState(() {
            _errorMessage = 'Conversation not found or has been deleted.';
            _loading = false;
          });
        }
        return;
      }

      // Security check: Verify authenticated caller is an authorized member
      final isCallerMember =
          members.any((m) => m['user_id'] == widget.currentUserId);
      if (!isCallerMember) {
        if (mounted) {
          debugPrint(
            '[NotificationTap] ❌ ChatRouteResolver: Caller ${widget.currentUserId} is not authorized for chatId: ${widget.chatId}',
          );
          setState(() {
            _errorMessage =
                'Access denied: You are not a participant in this conversation.';
            _loading = false;
          });
        }
        return;
      }

      final isGroup = chatRow != null && chatRow['type'] == 'group';
      if (isGroup) {
        final groupTitle = (chatRow['title'] as String?)?.trim();
        final resolvedTitle = (groupTitle != null && groupTitle.isNotEmpty)
            ? groupTitle
            : widget.initialContactName;
        final avatar = chatRow['avatar_url'] as String?;

        if (mounted) {
          debugPrint(
            '[NotificationTap] ChatRouteResolver: resolved group from Supabase -> title: "$resolvedTitle"',
          );
          setState(() {
            _isGroup = true;
            _resolvedPeerId = '';
            _resolvedContactName = resolvedTitle;
            _resolvedContactAvatar = avatar ?? widget.initialContactAvatar;
            _loading = false;
          });
        }
        return;
      }

      // Identify peer participant for direct conversation
      final peer = members.firstWhere(
        (m) => m['user_id'] != widget.currentUserId,
        orElse: () => <String, dynamic>{},
      );

      final peerId = peer['user_id'] as String? ?? '';
      if (peerId.isEmpty) {
        if (mounted) {
          debugPrint(
            '[NotificationTap] ❌ ChatRouteResolver: Peer user_id not found in chat_members',
          );
          setState(() {
            _errorMessage = 'Conversation participant not found.';
            _loading = false;
          });
        }
        return;
      }

      final profile = peer['profile'] as Map<String, dynamic>? ?? {};
      final phone = (profile['phone_e164'] as String?)?.trim();
      final avatar = profile['avatar_url'] as String?;

      if (mounted) {
        final contacts =
            ref.read(contactsDataControllerProvider).cachedMatched;
        final resolvedName = ContactIdentityResolver.resolveIdentity(
          phoneE164: phone,
          contacts: contacts,
          fallback: widget.initialContactName,
        );
        debugPrint(
          '[NotificationTap] ChatRouteResolver: resolved from Supabase chat_members -> peerId: $peerId, contactName: "$resolvedName"',
        );
        setState(() {
          _isGroup = false;
          _resolvedPeerId = peerId;
          _resolvedContactName = resolvedName;
          _resolvedContactAvatar = avatar ?? widget.initialContactAvatar;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint(
          '[NotificationTap] ❌ ChatRouteResolver error resolving conversation: $e',
        );
        setState(() {
          _errorMessage = 'Unable to open conversation: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null || (!_isGroup && _resolvedPeerId == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Unable to load conversation',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/chats'),
                  child: const Text('Back to Chats'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ChatRouteObserver(
      chatId: widget.chatId,
      child: ChatScreen(
        chatId: widget.chatId,
        currentUserId: widget.currentUserId,
        peerUserId: _resolvedPeerId ?? '',
        isGroup: _isGroup,
        contactName: _resolvedContactName ?? widget.initialContactName,
        contactAvatar: _resolvedContactAvatar ?? widget.initialContactAvatar,
      ),
    );
  }
}
