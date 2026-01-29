import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:instant_messenger/models/user_presence.dart';

/// Handles ONLY presence (online / last seen)
/// No UI, no chat logic, no state mutation outside presence
class ChatPresenceController {
  bool _presenceReady = false;

  /// Used by UI to avoid startup jitter
  bool get presenceReady => _presenceReady;

  /// Watch other user's presence
  /// Spark-safe, jitter-safe
  Stream<UserPresence> watchPresence(String otherUid) async* {
    // ⛔ Ignore first cached Firestore frame
    await Future.delayed(const Duration(milliseconds: 120));

    _presenceReady = true;

    yield* FirebaseFirestore.instance
        .collection('users')
        .doc(otherUid)
        .snapshots()
        .map((doc) {
          final data = doc.data();

          if (data == null) {
            return const UserPresence(online: false);
          }

          return UserPresence.fromMap(data);
        });
  }
}
