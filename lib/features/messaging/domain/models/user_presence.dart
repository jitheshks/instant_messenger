class UserPresence {
  final bool online;
  final DateTime? lastSeen;

  const UserPresence({required this.online, this.lastSeen});

  factory UserPresence.fromMap(Map<String, dynamic> data) {
    final rawSeen = data['last_seen'] ?? data['lastSeen'];
    DateTime? parsedDate;
    if (rawSeen is DateTime) {
      parsedDate = rawSeen;
    } else if (rawSeen is String && rawSeen.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawSeen);
    }

    return UserPresence(
      online: data['online'] == true || data['is_online'] == true,
      lastSeen: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'online': online,
      if (lastSeen != null) 'last_seen': lastSeen!.toIso8601String(),
    };
  }
}
