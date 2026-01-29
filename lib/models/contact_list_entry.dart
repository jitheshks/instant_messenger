class ContactListEntry {
  final String? uid; // null if not registered
  final String displayName; // profile or fallback device name
  final String? bio;
  final String? avatarUrl;
  final String? phoneE164;

  const ContactListEntry({
    required this.displayName,
    this.uid,
    this.bio,
    this.avatarUrl,
    this.phoneE164,
  });

  /// 🔥 Firestore → Model (snake_case → camelCase)
  factory ContactListEntry.fromFirestore({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    return ContactListEntry(
      uid: docId,

      // ✅ READ snake_case ONLY
      displayName: (data['display_name'] as String?)?.trim() ?? '',
      bio: (data['about'] as String?)?.trim(),
      avatarUrl: (data['avatar_url'] as String?)?.trim(), // ✅ KEEP
      phoneE164: (data['phone_e164'] as String?)?.trim(),
    );
  }

  /// Model → cache / local JSON (camelCase only)
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'bio': bio,
        'avatarUrl': avatarUrl,
        'phoneE164': phoneE164,
      };

  ContactListEntry copyWith({
    String? uid,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? phoneE164,
  }) {
    return ContactListEntry(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneE164: phoneE164 ?? this.phoneE164,
    );
  }
}
