import 'package:flutter/foundation.dart';
import 'package:instant_messenger/features/profile/domain/models/group_profile_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository managing group metadata, membership synchronization,
/// role assignments, and member management backed by Supabase.
class GroupRepository {
  final SupabaseClient? _supabaseClient;

  GroupRepository({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _sb => _supabaseClient ?? Supabase.instance.client;

  /// Fetches group metadata and member details for [chatId].
  Future<GroupProfileDetails?> fetchGroupDetails(
    String chatId,
    String currentUserId,
  ) async {
    try {
      // 1. Fetch group chat record
      final chatRow = await _sb
          .from('chats')
          .select('id, title, avatar_url, created_by, created_at')
          .eq('id', chatId)
          .maybeSingle();

      if (chatRow == null) return null;

      final title = (chatRow['title'] as String?)?.trim() ?? 'Group';
      final avatarUrl = (chatRow['avatar_url'] as String?)?.trim();
      final createdBy = chatRow['created_by'] as String?;
      final createdAtStr = chatRow['created_at'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr)?.toLocal()
          : null;

      // 2. Fetch group members with linked profiles
      final memberRows = await _sb
          .from('chat_members')
          .select(
            'user_id, role, muted, joined_at, profiles(id, display_name, avatar_url, phone_e164, about)',
          )
          .eq('chat_id', chatId);

      final members = <GroupMemberDetails>[];
      var isMuted = false;
      var isCurrentUserAdmin = false;

      for (final raw in (memberRows as List)) {
        final m = raw as Map<String, dynamic>;
        final uid = m['user_id'] as String;
        final role = (m['role'] as String?) ?? 'member';
        final isSelf = uid == currentUserId;

        if (isSelf) {
          isMuted = (m['muted'] as bool?) ?? false;
          if (role == 'admin') {
            isCurrentUserAdmin = true;
          }
        }

        final profile = m['profiles'] as Map<String, dynamic>?;
        final displayName =
            (profile?['display_name'] as String?)?.trim() ?? 'Member';
        final phone = (profile?['phone_e164'] as String?)?.trim();
        final memberAvatar = (profile?['avatar_url'] as String?)?.trim();
        final about = (profile?['about'] as String?)?.trim();
        final joinedAtStr = m['joined_at'] as String?;
        final joinedAt = joinedAtStr != null
            ? DateTime.tryParse(joinedAtStr)?.toLocal()
            : null;

        members.add(
          GroupMemberDetails(
            userId: uid,
            role: role,
            displayName: displayName,
            phoneE164: phone,
            avatarUrl: memberAvatar,
            about: about,
            isCurrentUser: isSelf,
            joinedAt: joinedAt,
          ),
        );
      }

      // Sort members: Admins first, then alphabetically, with "You" at top
      members.sort((a, b) {
        if (a.isCurrentUser) return -1;
        if (b.isCurrentUser) return 1;
        if (a.isAdmin && !b.isAdmin) return -1;
        if (!a.isAdmin && b.isAdmin) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

      return GroupProfileDetails(
        id: chatId,
        title: title,
        avatarUrl: avatarUrl,
        createdBy: createdBy,
        createdAt: createdAt,
        isCurrentUserAdmin: isCurrentUserAdmin,
        isMuted: isMuted,
        members: members,
      );
    } catch (e) {
      debugPrint('[GroupRepo] Failed to fetch group details: $e');
      return null;
    }
  }

  /// Updates group title if caller is an admin or group creator.
  Future<void> updateGroupTitle(String chatId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;

    await _sb.from('chats').update({
      'title': trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', chatId);
  }

  /// Updates group avatar if caller is an admin or group creator.
  Future<void> updateGroupAvatar(String chatId, String avatarUrl) async {
    final trimmed = avatarUrl.trim();
    await _sb.from('chats').update({
      'avatar_url': trimmed.isEmpty ? null : trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', chatId);
  }

  /// Promotes or demotes a group member via Supabase RPC `set_chat_member_role`.
  Future<void> setMemberRole(
    String chatId,
    String targetUserId,
    String newRole,
  ) async {
    await _sb.rpc(
      'set_chat_member_role',
      params: {
        'p_chat_id': chatId,
        'p_target_user_id': targetUserId,
        'p_new_role': newRole,
      },
    );
  }

  /// Removes a group member via Supabase RPC `remove_chat_member`.
  Future<void> removeMember(String chatId, String targetUserId) async {
    await _sb.rpc(
      'remove_chat_member',
      params: {
        'p_chat_id': chatId,
        'p_target_user_id': targetUserId,
      },
    );
  }

  /// Adds a new member to an existing group.
  Future<void> addMember(String chatId, String targetUserId) async {
    await _sb.from('chat_members').insert({
      'chat_id': chatId,
      'user_id': targetUserId,
      'role': 'member',
    });
  }

  /// Toggles notification mute for current user on [chatId].
  Future<void> toggleMute(
    String chatId,
    String currentUserId,
    bool isMuted,
  ) async {
    await _sb
        .from('chat_members')
        .update({'muted': isMuted})
        .eq('chat_id', chatId)
        .eq('user_id', currentUserId);
  }

  /// Leaves the group via Supabase RPC `leave_chat`.
  Future<void> leaveGroup(String chatId) async {
    await _sb.rpc('leave_chat', params: {'p_chat_id': chatId});
  }
}
