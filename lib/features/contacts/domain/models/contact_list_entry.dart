class ContactListEntry {
  final String? uid; // null if not registered
  final String displayName; // profile or fallback device name
  final String? bio;
  final String? avatarUrl;
  final String? phoneE164;
  final String? savedName; // Saved name from device address book
  final bool isSaved; // True if this contact is saved in device address book

  const ContactListEntry({
    required this.displayName,
    this.uid,
    this.bio,
    this.avatarUrl,
    this.phoneE164,
    this.savedName,
    bool? isSaved,
  }) : isSaved = isSaved ?? (savedName != null && savedName != '');

  /// Supabase RPC / table row → model
  factory ContactListEntry.fromSupabase(
    Map<String, dynamic> row, {
    String? fallbackSavedName,
  }) {
    final cleanSaved =
        (fallbackSavedName != null && fallbackSavedName.trim().isNotEmpty)
            ? fallbackSavedName.trim()
            : null;
    final remoteName = (row['display_name'] as String?)?.trim();
    final displayName = cleanSaved ??
        (remoteName != null && remoteName.isNotEmpty
            ? remoteName
            : (row['phone_e164'] as String? ?? ''));

    return ContactListEntry(
      uid: row['uid']?.toString() ?? row['id']?.toString(),
      displayName: displayName,
      savedName: cleanSaved,
      isSaved: cleanSaved != null,
      bio: (row['about'] as String?)?.trim(),
      avatarUrl: (row['avatar_url'] as String?)?.trim(),
      phoneE164: (row['phone_e164'] as String?)?.trim(),
    );
  }
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'bio': bio,
    'avatarUrl': avatarUrl,
    'phoneE164': phoneE164,
    'savedName': savedName,
    'isSaved': isSaved,
  };

  factory ContactListEntry.fromJson(Map<String, dynamic> json) {
    return ContactListEntry(
      uid: json['uid'] as String?,
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      phoneE164: json['phoneE164'] as String?,
      savedName: json['savedName'] as String?,
      isSaved: json['isSaved'] as bool?,
    );
  }

  ContactListEntry copyWith({
    String? uid,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? phoneE164,
    String? savedName,
    bool? isSaved,
  }) {
    return ContactListEntry(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneE164: phoneE164 ?? this.phoneE164,
      savedName: savedName ?? this.savedName,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}
