import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';

/// Presentation-ready domain model for an individual group member.
class GroupMemberDetails {
  final String userId;
  final String role; // 'admin' | 'member'
  final String displayName;
  final String? phoneE164;
  final String? avatarUrl;
  final String? about;
  final bool isCurrentUser;
  final DateTime? joinedAt;

  const GroupMemberDetails({
    required this.userId,
    required this.role,
    required this.displayName,
    this.phoneE164,
    this.avatarUrl,
    this.about,
    this.isCurrentUser = false,
    this.joinedAt,
  });

  bool get isAdmin => role == 'admin';

  GroupMemberDetails copyWith({
    String? userId,
    String? role,
    String? displayName,
    String? phoneE164,
    String? avatarUrl,
    String? about,
    bool? isCurrentUser,
    DateTime? joinedAt,
  }) {
    return GroupMemberDetails(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      phoneE164: phoneE164 ?? this.phoneE164,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}

/// Presentation-ready domain model for group profile and membership details.
class GroupProfileDetails {
  final String id; // chatId
  final String title;
  final String? avatarUrl;
  final String? description;
  final String? createdBy;
  final DateTime? createdAt;
  final bool isCurrentUserAdmin;
  final bool isMuted;
  final List<GroupMemberDetails> members;
  final ProfileMediaSummary mediaSummary;

  const GroupProfileDetails({
    required this.id,
    required this.title,
    this.avatarUrl,
    this.description,
    this.createdBy,
    this.createdAt,
    this.isCurrentUserAdmin = false,
    this.isMuted = false,
    this.members = const [],
    this.mediaSummary = const ProfileMediaSummary(),
  });

  int get memberCount => members.length;

  GroupProfileDetails copyWith({
    String? id,
    String? title,
    String? avatarUrl,
    String? description,
    String? createdBy,
    DateTime? createdAt,
    bool? isCurrentUserAdmin,
    bool? isMuted,
    List<GroupMemberDetails>? members,
    ProfileMediaSummary? mediaSummary,
  }) {
    return GroupProfileDetails(
      id: id ?? this.id,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isCurrentUserAdmin: isCurrentUserAdmin ?? this.isCurrentUserAdmin,
      isMuted: isMuted ?? this.isMuted,
      members: members ?? this.members,
      mediaSummary: mediaSummary ?? this.mediaSummary,
    );
  }
}
