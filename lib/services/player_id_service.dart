import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerIdService {
  /// Returns all active player ids for a user uid.
  /// Checks multiple common locations for compatibility.
  static Future<List<String>> fetchPlayerIdsForUid(String uid) async {
    final db = FirebaseFirestore.instance;
    final docSnap = await db.collection('users').doc(uid).get();
    final data = docSnap.data() ?? {};

    final ids = <String>{};

    // Top-level arrays
    final dynamic arr = data['player_ids'] ?? data['playerIds'];
    if (arr is List) {
      for (final e in arr) {
        if (e is String && e.isNotEmpty) ids.add(e);
      }
    }

    // Single id fields
    final single = data['player_id'] ?? data['playerId'];
    if (single is String && single.isNotEmpty) ids.add(single);

    // players subcollection
    try {
      final players = await db.collection('users').doc(uid).collection('players').get();
      for (final p in players.docs) {
        final pid = p.data()['player_id'] as String?;
        final subscribed = p.data()['subscribed'];
        if (pid != null && pid.isNotEmpty) {
          // only include if not explicitly unsubscribed
          if (subscribed == null || subscribed == true) ids.add(pid);
        }
      }
    } catch (_) {
      // ignore subcollection read errors
    }

    return ids.toList();
  }
}
