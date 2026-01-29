class UserProfile {
  final String uid;
  final String displayName;
  final String bio;
  final String phoneE164;
  final String? avatarUrl;
  final List<String> links;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.bio,
    required this.phoneE164,
    this.avatarUrl,
    this.links = const [],
  });

  /// 🔥 Firestore → Model (snake_case → camelCase)
  factory UserProfile.fromMap(
    String uid,
    Map<String, dynamic> m, {
    String? fallbackPhone,
  }) {
    return UserProfile(
      uid: uid,

      // ✅ READ snake_case ONLY
      displayName: (m['display_name'] as String?)?.trim() ?? '',
      bio: (m['about'] as String?)?.trim() ?? '',
      phoneE164:
          (m['phone_e164'] as String?)?.trim() ?? (fallbackPhone ?? ''),
      avatarUrl: (m['avatar_url'] as String?)?.trim(),

      links: (m['links'] is List)
          ? (m['links'] as List).map((e) => e.toString()).toList()
          : const <String>[],
    );
  }

  /// Model → cache / local JSON (camelCase only)
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'bio': bio,
        'phoneE164': phoneE164,
        'avatarUrl': avatarUrl,
        'links': links,
      };

  UserProfile copyWith({
    String? displayName,
    String? bio,
    String? phoneE164,
    String? avatarUrl,
    List<String>? links,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      phoneE164: phoneE164 ?? this.phoneE164,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      links: links ?? this.links,
    );
  }
}
