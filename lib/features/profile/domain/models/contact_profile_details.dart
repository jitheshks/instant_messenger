import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';

/// Presentation-ready domain model representing a direct contact's profile details.
class ContactProfileDetails {
  final String chatId;
  final String peerUserId;
  final String resolvedDisplayName;
  final String? phoneE164;
  final String? avatarUrl;
  final String? about;
  final bool isMuted;
  final ProfileMediaSummary mediaSummary;

  const ContactProfileDetails({
    required this.chatId,
    required this.peerUserId,
    required this.resolvedDisplayName,
    this.phoneE164,
    this.avatarUrl,
    this.about,
    this.isMuted = false,
    this.mediaSummary = const ProfileMediaSummary(),
  });

  ContactProfileDetails copyWith({
    String? chatId,
    String? peerUserId,
    String? resolvedDisplayName,
    String? phoneE164,
    String? avatarUrl,
    String? about,
    bool? isMuted,
    ProfileMediaSummary? mediaSummary,
  }) {
    return ContactProfileDetails(
      chatId: chatId ?? this.chatId,
      peerUserId: peerUserId ?? this.peerUserId,
      resolvedDisplayName: resolvedDisplayName ?? this.resolvedDisplayName,
      phoneE164: phoneE164 ?? this.phoneE164,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
      isMuted: isMuted ?? this.isMuted,
      mediaSummary: mediaSummary ?? this.mediaSummary,
    );
  }
}
