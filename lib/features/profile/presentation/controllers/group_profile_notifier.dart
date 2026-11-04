import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/profile/data/group_repository.dart';
import 'package:instant_messenger/features/profile/domain/models/group_profile_details.dart';
import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';

class GroupProfileArgs {
  final String chatId;
  final String currentUserId;
  final String initialTitle;
  final String initialAvatar;

  const GroupProfileArgs({
    required this.chatId,
    required this.currentUserId,
    required this.initialTitle,
    this.initialAvatar = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupProfileArgs &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          currentUserId == other.currentUserId;

  @override
  int get hashCode => chatId.hashCode ^ currentUserId.hashCode;
}

class GroupProfileState {
  final bool isLoading;
  final String? errorMessage;
  final GroupProfileDetails? details;
  final int selectedTabIndex; // 0: Members, 1: Media, 2: Settings
  final String memberSearchQuery;

  const GroupProfileState({
    this.isLoading = false,
    this.errorMessage,
    this.details,
    this.selectedTabIndex = 0,
    this.memberSearchQuery = '',
  });

  GroupProfileState copyWith({
    bool? isLoading,
    String? errorMessage,
    GroupProfileDetails? details,
    int? selectedTabIndex,
    String? memberSearchQuery,
  }) {
    return GroupProfileState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      details: details ?? this.details,
      selectedTabIndex: selectedTabIndex ?? this.selectedTabIndex,
      memberSearchQuery: memberSearchQuery ?? this.memberSearchQuery,
    );
  }

  /// Members filtered by the active member search query.
  List<GroupMemberDetails> get filteredMembers {
    final list = details?.members ?? const [];
    final q = memberSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((m) {
      final nameMatches = m.displayName.toLowerCase().contains(q);
      final phoneMatches = m.phoneE164?.toLowerCase().contains(q) ?? false;
      return nameMatches || phoneMatches;
    }).toList();
  }
}

class GroupProfileNotifier extends Notifier<GroupProfileState> {
  final GroupProfileArgs arg;
  GroupProfileNotifier(this.arg);

  late final GroupRepository _groupRepo;
  MessagesRepository? _messagesRepo;
  MessagesStore? _messagesStore;

  @override
  GroupProfileState build() {
    _groupRepo = ref.watch(groupRepositoryProvider);
    _messagesRepo = ref.watch(messagesRepositoryProvider);
    _messagesStore = _messagesRepo?.messagesStore;

    final initialDetails = GroupProfileDetails(
      id: arg.chatId,
      title: arg.initialTitle,
      avatarUrl: arg.initialAvatar.isNotEmpty ? arg.initialAvatar : null,
    );

    Future.microtask(() => loadGroup());

    return GroupProfileState(isLoading: true, details: initialDetails);
  }

  Future<void> loadGroup() async {
    try {
      final details = await _groupRepo.fetchGroupDetails(
        arg.chatId,
        arg.currentUserId,
      );

      if (details == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Group details unavailable.',
        );
        return;
      }

      // Resolve member identities against local saved contacts
      final contacts = ref.read(contactsDataControllerProvider).cachedMatched;
      final resolvedMembers = details.members.map((m) {
        if (m.isCurrentUser) {
          return m.copyWith(displayName: 'You');
        }
        final name = ContactIdentityResolver.resolveIdentity(
          phoneE164: m.phoneE164,
          userId: m.userId,
          contacts: contacts,
          fallback: m.displayName,
        );
        return m.copyWith(displayName: name);
      }).toList();

      // Extract shared group media (all locally cached)
      final localMsgs =
          _messagesStore?.getMessagesForChat(arg.chatId, limit: null) ?? [];
      final mediaSummary = ProfileMediaService.extractSummary(localMsgs);

      final enriched = details.copyWith(
        members: resolvedMembers,
        mediaSummary: mediaSummary,
      );

      state = state.copyWith(isLoading: false, details: enriched);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load group: $e',
      );
    }
  }

  void setTab(int index) {
    if (state.selectedTabIndex != index) {
      state = state.copyWith(selectedTabIndex: index);
    }
  }

  void setMemberSearch(String query) {
    state = state.copyWith(memberSearchQuery: query);
  }

  Future<bool> updateTitle(String newTitle) async {
    try {
      await _groupRepo.updateGroupTitle(arg.chatId, newTitle);
      state = state.copyWith(
        details: state.details?.copyWith(title: newTitle),
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update group name: $e');
      return false;
    }
  }

  Future<bool> updateAvatar(String newAvatarUrl) async {
    try {
      await _groupRepo.updateGroupAvatar(arg.chatId, newAvatarUrl);
      state = state.copyWith(
        details: state.details?.copyWith(avatarUrl: newAvatarUrl),
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update avatar: $e');
      return false;
    }
  }

  Future<bool> setMemberRole(String targetUserId, String newRole) async {
    try {
      await _groupRepo.setMemberRole(arg.chatId, targetUserId, newRole);
      final updated = state.details?.members.map((m) {
        if (m.userId == targetUserId) {
          return m.copyWith(role: newRole);
        }
        return m;
      }).toList();

      if (updated != null) {
        state = state.copyWith(
          details: state.details?.copyWith(members: updated),
        );
      }
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update role: $e');
      return false;
    }
  }

  Future<bool> removeMember(String targetUserId) async {
    try {
      await _groupRepo.removeMember(arg.chatId, targetUserId);
      final updated = state.details?.members
          .where((m) => m.userId != targetUserId)
          .toList();

      if (updated != null) {
        state = state.copyWith(
          details: state.details?.copyWith(members: updated),
        );
      }
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove member: $e');
      return false;
    }
  }

  Future<bool> addMember(String targetUserId) async {
    try {
      await _groupRepo.addMember(arg.chatId, targetUserId);
      await loadGroup();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to add member: $e');
      return false;
    }
  }

  Future<void> toggleMute(bool isMuted) async {
    final current = state.details;
    if (current == null) return;

    state = state.copyWith(details: current.copyWith(isMuted: isMuted));
    try {
      await _groupRepo.toggleMute(arg.chatId, arg.currentUserId, isMuted);
    } catch (_) {
      state = state.copyWith(details: current.copyWith(isMuted: !isMuted));
    }
  }

  Future<bool> leaveGroup() async {
    try {
      await _groupRepo.leaveGroup(arg.chatId);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to leave group: $e');
      return false;
    }
  }

  Future<void> clearChat() async {
    await _messagesStore?.clearChatMessages(arg.chatId);
    final current = state.details;
    if (current != null) {
      state = state.copyWith(
        details: current.copyWith(
          mediaSummary: const ProfileMediaSummary(),
        ),
      );
    }
  }
}
