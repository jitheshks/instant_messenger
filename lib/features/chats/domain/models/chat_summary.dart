import 'package:instant_messenger/core/config/supabase_config.dart';

class ChatSummary {
  final String id; // chatId
  final String lastMessage;
  final DateTime lastTime;
  final int unread;
  final bool muted;

  // Identity
  final String otherUserId; // peer uid
  final String? otherPhoneE164; // WhatsApp-style

  final List<String> members;

  // Message status
  final String lastSenderId;
  final int lastMessageStatus; // 0–3
  final String? lastMessageId;

  // UI
  final String? avatarUrl;
  final bool isGroup;
  final String? title;

  const ChatSummary({
    required this.id,
    required this.lastMessage,
    required this.lastTime,
    required this.unread,
    required this.muted,
    required this.otherUserId,
    required this.members,
    required this.lastSenderId,
    required this.lastMessageStatus,
    this.otherPhoneE164,
    this.avatarUrl,
    this.lastMessageId,
    this.isGroup = false,
    this.title,
  });

  /// Derive peer uid from members
  static String deriveOtherUserId(List<String> members, [String? currentUid]) {
    if (members.length != 2) return '';
    currentUid ??= SupabaseConfig.currentUserId ?? '';
    return members.firstWhere((m) => m != currentUid, orElse: () => '');
  }

  /// Legacy deserializer retained for caller compatibility until ChatsRepository is cleaned.
  @Deprecated(
    'Legacy deserializer. Kept until ChatsRepository is cleaned in Step 2C.',
  )
  factory ChatSummary.fromDoc(dynamic doc) {
    final dynamic rawData = (doc as dynamic).data();
    final data = (rawData is Map)
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    final lastMsg = data['lastMessage'] as String? ?? '';
    final unread = data['unread'] as int? ?? 0;
    final muted = data['muted'] as bool? ?? false;

    final avatar = data['avatar_url'] as String?;
    final otherPhoneE164 = data['other_phone_e164'] as String?;

    final members =
        (data['members'] as List?)?.map((e) => e.toString()).toList() ?? [];

    String other = data['otherUserId'] as String? ?? '';
    if (other.isEmpty) {
      other = ChatSummary.deriveOtherUserId(members);
    }

    final lastTime = _parseDate(data['lastTime']);
    final lastSenderId = data['lastSenderId'] as String? ?? '';
    final lastMessageStatus = data['lastMessageStatus'] as int? ?? 0;

    return ChatSummary(
      id: (doc as dynamic).id?.toString() ?? '',
      lastMessage: lastMsg,
      lastTime: lastTime,
      unread: unread,
      muted: muted,
      avatarUrl: avatar,
      otherUserId: other,
      otherPhoneE164: otherPhoneE164,
      members: members,
      lastSenderId: lastSenderId,
      lastMessageStatus: lastMessageStatus,
    );
  }

  /// Supabase row → model
  factory ChatSummary.fromSupabase(
    Map<String, dynamic> row,
    String currentUid,
  ) {
    final chatId = row['id']?.toString() ?? row['chat_id']?.toString() ?? '';
    final lastMsg = row['last_message'] as String? ?? '';
    final lastTime = _parseDate(row['last_message_time'] ?? row['updated_at']);

    final rawMembers = row['chat_members'] as List? ?? [];
    final members = <String>[];
    String otherUserId = '';
    String? otherPhoneE164;
    String? avatar = row['avatar_url'] as String?;
    int unread = 0;
    bool muted = false;

    for (final m in rawMembers) {
      if (m is Map) {
        final mUid = m['user_id']?.toString() ?? '';
        if (mUid.isNotEmpty) members.add(mUid);

        if (mUid == currentUid) {
          unread = m['unread_count'] as int? ?? 0;
          muted = m['muted'] as bool? ?? false;
        } else {
          otherUserId = mUid;
          final profile = m['profile'] as Map?;
          if (profile != null) {
            otherPhoneE164 = profile['phone_e164'] as String?;
            avatar ??= profile['avatar_url'] as String?;
          }
        }
      }
    }

    if (otherUserId.isEmpty && members.isNotEmpty) {
      otherUserId = members.firstWhere(
        (m) => m != currentUid,
        orElse: () => '',
      );
    }

    final lastSenderId = row['last_sender_id']?.toString() ?? '';
    final lastMessageStatus = row['last_message_status'] as int? ?? 0;
    final lastMessageId = row['last_message_id']?.toString();
    final isGroup = row['type'] == 'group';
    final title = row['title'] as String?;

    return ChatSummary(
      id: chatId,
      lastMessage: lastMsg,
      lastTime: lastTime,
      unread: unread,
      muted: muted,
      avatarUrl: avatar,
      otherUserId: otherUserId,
      otherPhoneE164: otherPhoneE164,
      members: members,
      lastSenderId: lastSenderId,
      lastMessageStatus: lastMessageStatus,
      lastMessageId: lastMessageId,
      isGroup: isGroup,
      title: title,
    );
  }

  // Cache JSON → model
  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final members =
        (json['members'] as List?)?.map((e) => e.toString()).toList() ?? [];

    String other = json['otherUserId'] ?? '';
    if (other.isEmpty) {
      other = deriveOtherUserId(members);
    }
    return ChatSummary(
      id: json['id'] ?? '',
      lastMessage: json['lastMessage'] ?? '',
      lastTime: _parseDate(json['lastTime']),
      unread: json['unread'] ?? 0,
      muted: json['muted'] ?? false,
      avatarUrl: json['avatarUrl'],
      otherUserId: other,
      otherPhoneE164: json['otherPhoneE164'],
      members: members,
      lastSenderId: json['lastSenderId'] ?? '',
      lastMessageStatus: json['lastMessageStatus'] ?? 0,
      lastMessageId: json['lastMessageId'] as String?,
      isGroup: json['isGroup'] == true,
      title: json['title'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lastMessage': lastMessage,
    'lastTime': lastTime.toIso8601String(),
    'unread': unread,
    'muted': muted,
    'avatarUrl': avatarUrl,
    'otherUserId': otherUserId,
    'otherPhoneE164': otherPhoneE164,
    'members': members,
    'lastSenderId': lastSenderId,
    'lastMessageStatus': lastMessageStatus,
    if (lastMessageId != null) 'lastMessageId': lastMessageId,
    'isGroup': isGroup,
    if (title != null) 'title': title,
  };

  ChatSummary copyWith({
    String? id,
    String? lastMessage,
    DateTime? lastTime,
    int? unread,
    bool? muted,
    String? avatarUrl,
    String? otherUserId,
    String? otherPhoneE164,
    List<String>? members,
    String? lastSenderId,
    int? lastMessageStatus,
    String? lastMessageId,
    bool? isGroup,
    String? title,
  }) {
    return ChatSummary(
      id: id ?? this.id,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTime: lastTime ?? this.lastTime,
      unread: unread ?? this.unread,
      muted: muted ?? this.muted,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      otherUserId: otherUserId ?? this.otherUserId,
      otherPhoneE164: otherPhoneE164 ?? this.otherPhoneE164,
      members: members ?? this.members,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      isGroup: isGroup ?? this.isGroup,
      title: title ?? this.title,
    );
  }
}

DateTime _parseDate(dynamic v) {
  if (v is DateTime) return v;
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
  }
  if (v is int) {
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
  if (v != null) {
    try {
      final date = (v as dynamic).toDate();
      if (date is DateTime) return date;
    } catch (_) {}
  }

  // IMPORTANT: never return epoch for chat list
  return DateTime.now();
}
