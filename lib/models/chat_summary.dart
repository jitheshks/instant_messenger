import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatSummary {
  final String id; // chatId
  final String lastMessage;
  final DateTime lastTime;
  final int unread;
  final bool muted;

  // 🔥 Identity
  final String otherUserId;        // peer uid
  final String? otherPhoneE164;    // 🔥 ADD (WhatsApp-style)

  final List<String> members;

  // 🔥 Message status
  final String lastSenderId;
  final int lastMessageStatus; // 0–3

  // 🔥 UI
  final String? avatarUrl;
  final IconData? icon;
  final Color? iconBg;

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
    this.otherPhoneE164, // 🔥 ADD
    this.avatarUrl,
    this.icon,
    this.iconBg,
  });



  /// Derive peer uid from members
  static String deriveOtherUserId(List<String> members, [String? currentUid]) {
    if (members.length != 2) return '';
    currentUid ??= FirebaseAuth.instance.currentUser?.uid ?? '';
    return members.firstWhere((m) => m != currentUid, orElse: () => '');
  }

// Firestore → model (MERGED & SAFE)
factory ChatSummary.fromDoc(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};

  final lastMsg = data['lastMessage'] as String? ?? '';
  final unread = data['unread'] as int? ?? 0;
  final muted = data['muted'] as bool? ?? false;

  // ✅ snake_case from Firestore
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
    id: doc.id,
    lastMessage: lastMsg,
    lastTime: lastTime,
    unread: unread,
    muted: muted,
    avatarUrl: avatar,
    otherUserId: other,
    otherPhoneE164: otherPhoneE164, // 🔥 ADDED
    members: members,
    lastSenderId: lastSenderId,
    lastMessageStatus: lastMessageStatus,
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
  otherPhoneE164: json['otherPhoneE164'], // 🔥 ADD THIS
  members: members,
  lastSenderId: json['lastSenderId'] ?? '',
  lastMessageStatus: json['lastMessageStatus'] ?? 0,
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
  'otherPhoneE164': otherPhoneE164, // 🔥 ADD THIS
  'members': members,
  'lastSenderId': lastSenderId,
  'lastMessageStatus': lastMessageStatus,
};
ChatSummary copyWith({
  String? id,
  String? lastMessage,
  DateTime? lastTime,
  int? unread,
  bool? muted,
  String? avatarUrl,
  IconData? icon,
  Color? iconBg,
  String? otherUserId,
  String? otherPhoneE164, // 🔥 ADD
  List<String>? members,
  String? lastSenderId,
  int? lastMessageStatus,
}) {
  return ChatSummary(
    id: id ?? this.id,
    lastMessage: lastMessage ?? this.lastMessage,
    lastTime: lastTime ?? this.lastTime,
    unread: unread ?? this.unread,
    muted: muted ?? this.muted,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    icon: icon ?? this.icon,
    iconBg: iconBg ?? this.iconBg,
    otherUserId: otherUserId ?? this.otherUserId,
    otherPhoneE164: otherPhoneE164 ?? this.otherPhoneE164, // 🔥 ADD
    members: members ?? this.members,
    lastSenderId: lastSenderId ?? this.lastSenderId,
    lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
  );
}

}

DateTime _parseDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
  }

  // 🔥 IMPORTANT: never return epoch for chat list
  return DateTime.now();
}
