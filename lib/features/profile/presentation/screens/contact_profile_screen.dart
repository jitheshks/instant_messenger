import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/messaging/presentation/widgets/chat_app_bar_actions.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/contact_profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_action_buttons.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_header.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_media_section.dart';
import 'package:instant_messenger/features/profile/presentation/widgets/profile_settings_tiles.dart';

/// Screen displaying individual contact profile information, calling shortcuts,
/// shared media attachments, chat settings, and contact management actions.
class ContactProfileScreen extends ConsumerWidget {
  final String chatId;
  final String peerUserId;
  final String peerName;
  final String avatarUrl;
  final String? phone;

  const ContactProfileScreen({
    super.key,
    required this.chatId,
    required this.peerUserId,
    required this.peerName,
    this.avatarUrl = '',
    this.phone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId =
        ref.watch(currentUserIdProvider) ?? SupabaseConfig.currentUserId ?? '';
    final args = ContactProfileArgs(
      chatId: chatId,
      peerUserId: peerUserId,
      currentUserId: currentUserId,
      initialName: peerName,
      initialAvatar: avatarUrl,
      initialPhone: phone,
    );

    final state = ref.watch(contactProfileControllerProvider(args));
    final notifier = ref.read(contactProfileControllerProvider(args).notifier);

    final details = state.details;
    final resolvedName = details?.resolvedDisplayName ?? peerName;
    final displayPhone = details?.phoneE164 ?? phone;
    final displayAvatar = details?.avatarUrl ?? avatarUrl;
    final about = details?.about;
    final isMuted = details?.isMuted ?? false;
    final mediaSummary = details?.mediaSummary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact info'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'share') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sharing $resolvedName\'s contact')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Share'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          children: [
            // 1. Profile Header
            ProfileHeader(
              displayName: resolvedName,
              phoneE164: displayPhone,
              avatarUrl: displayAvatar,
              about: about,
            ),

            // 2. Quick Actions: Audio, Video, Search
            ProfileActionButtons(
              actions: [
                ProfileActionButtonItem(
                  icon: Icons.call_outlined,
                  label: 'Audio',
                  onTap: () {
                    ChatAppBarActions.initiateCall(
                      context,
                      ref,
                      chatId,
                      peerUserId,
                      resolvedName,
                      CallType.audio,
                    );
                  },
                ),
                ProfileActionButtonItem(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: () {
                    ChatAppBarActions.initiateCall(
                      context,
                      ref,
                      chatId,
                      peerUserId,
                      resolvedName,
                      CallType.video,
                    );
                  },
                ),
                ProfileActionButtonItem(
                  icon: Icons.search,
                  label: 'Search',
                  onTap: () {
                    // Navigate back to chat with search intent
                    context.pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Media, Links, and Docs
            if (mediaSummary != null) ...[
              ProfileMediaSection(mediaSummary: mediaSummary),
              const SizedBox(height: 16),
            ],

            // 4. Settings Card
            ProfileSettingsCard(
              isMuted: isMuted,
              onMuteChanged: (val) {
                notifier.toggleMute(currentUserId, val);
              },
              contactName: resolvedName,
            ),
            const SizedBox(height: 16),

            // 5. Destructive Danger Actions Card
            ProfileDangerCard(
              contactName: resolvedName,
              onClearChat: () async {
                await notifier.clearChat();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat cleared on this device')),
                  );
                }
              },
              onBlock: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This feature is not available yet.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              onReport: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This feature is not available yet.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
