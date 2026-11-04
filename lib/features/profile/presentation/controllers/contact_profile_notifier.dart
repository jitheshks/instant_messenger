import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/persistence/stores/messages_store.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:instant_messenger/features/profile/data/group_repository.dart';
import 'package:instant_messenger/features/profile/data/user_service.dart';
import 'package:instant_messenger/features/profile/domain/models/contact_profile_details.dart';
import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';

class ContactProfileArgs {
  final String chatId;
  final String peerUserId;
  final String currentUserId;
  final String initialName;
  final String initialAvatar;
  final String? initialPhone;

  const ContactProfileArgs({
    required this.chatId,
    required this.peerUserId,
    this.currentUserId = '',
    required this.initialName,
    this.initialAvatar = '',
    this.initialPhone,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactProfileArgs &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          peerUserId == other.peerUserId &&
          currentUserId == other.currentUserId;

  @override
  int get hashCode =>
      chatId.hashCode ^ peerUserId.hashCode ^ currentUserId.hashCode;
}

class ContactProfileState {
  final bool isLoading;
  final String? errorMessage;
  final ContactProfileDetails? details;

  const ContactProfileState({
    this.isLoading = false,
    this.errorMessage,
    this.details,
  });

  ContactProfileState copyWith({
    bool? isLoading,
    String? errorMessage,
    ContactProfileDetails? details,
  }) {
    return ContactProfileState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      details: details ?? this.details,
    );
  }
}

class ContactProfileNotifier extends Notifier<ContactProfileState> {
  final ContactProfileArgs arg;
  ContactProfileNotifier(this.arg);

  late final UserService _userService;
  MessagesRepository? _messagesRepo;
  late final GroupRepository _groupRepo;
  MessagesStore? _messagesStore;

  @override
  ContactProfileState build() {
    _userService = ref.watch(userServiceProvider);
    _messagesRepo = ref.watch(messagesRepositoryProvider);
    _groupRepo = ref.watch(groupRepositoryProvider);
    _messagesStore = _messagesRepo?.messagesStore;

    // Initial state with fast-path fallback
    final contacts = ref.watch(contactsDataControllerProvider).cachedMatched;
    final resolvedName = ContactIdentityResolver.resolveIdentity(
      phoneE164: arg.initialPhone,
      userId: arg.peerUserId,
      contacts: contacts,
      fallback: arg.initialName,
    );

    final initialDetails = ContactProfileDetails(
      chatId: arg.chatId,
      peerUserId: arg.peerUserId,
      resolvedDisplayName: resolvedName,
      phoneE164: arg.initialPhone,
      avatarUrl: arg.initialAvatar.isNotEmpty ? arg.initialAvatar : null,
    );

    // Eagerly trigger full background profile load
    Future.microtask(() => loadProfile());

    return ContactProfileState(isLoading: true, details: initialDetails);
  }

  Future<void> loadProfile() async {
    try {
      final contacts = ref.read(contactsDataControllerProvider).cachedMatched;
      final peerProfile = await _userService.fetchUserProfile(arg.peerUserId);

      final phone = peerProfile?.phoneE164.isNotEmpty == true
          ? peerProfile!.phoneE164
          : arg.initialPhone;

      final resolvedName = ContactIdentityResolver.resolveIdentity(
        phoneE164: phone,
        userId: arg.peerUserId,
        contacts: contacts,
        fallback: peerProfile?.displayName.isNotEmpty == true
            ? peerProfile!.displayName
            : arg.initialName,
      );

      // Extract media items for this conversation from local store or repo (all locally cached)
      final localMsgs =
          _messagesStore?.getMessagesForChat(arg.chatId, limit: null) ?? [];
      final mediaSummary = ProfileMediaService.extractSummary(localMsgs);

      final details = ContactProfileDetails(
        chatId: arg.chatId,
        peerUserId: arg.peerUserId,
        resolvedDisplayName: resolvedName,
        phoneE164: phone,
        avatarUrl: peerProfile?.avatarUrl ?? (arg.initialAvatar.isNotEmpty ? arg.initialAvatar : null),
        about: peerProfile?.bio.isNotEmpty == true ? peerProfile!.bio : null,
        isMuted: state.details?.isMuted ?? false,
        mediaSummary: mediaSummary,
      );

      state = state.copyWith(isLoading: false, details: details);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load profile: $e',
      );
    }
  }

  Future<void> toggleMute(String currentUserId, bool isMuted) async {
    final current = state.details;
    if (current == null) return;

    state = state.copyWith(details: current.copyWith(isMuted: isMuted));
    try {
      await _groupRepo.toggleMute(arg.chatId, currentUserId, isMuted);
    } catch (_) {
      // Rollback on failure
      state = state.copyWith(details: current.copyWith(isMuted: !isMuted));
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
