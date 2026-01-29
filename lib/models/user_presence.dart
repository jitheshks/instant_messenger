import 'package:cloud_firestore/cloud_firestore.dart';

class UserPresence {
  final bool online;
  final DateTime? lastSeen;

  const UserPresence({
    required this.online,
    this.lastSeen,
  });

  factory UserPresence.fromMap(Map<String, dynamic> data) {
    return UserPresence(
      online: data['online'] == true,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
    );
  }
}
