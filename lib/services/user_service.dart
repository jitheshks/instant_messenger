import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class UserService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  UserService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  // ------------------------------------------------------------
  // CACHED SIGNED-IN PROFILE
  // ------------------------------------------------------------

  UserProfile? _me;

  // Public getters (used by notifications / UI)
  UserProfile? get currentProfile => _me;
  String? get displayName => _me?.displayName;
  String? get avatarUrl => _me?.avatarUrl;

  // ------------------------------------------------------------
  // PROFILE READS
  // ------------------------------------------------------------

  /// Live stream of the logged-in user's profile
  Stream<UserProfile> watchMe() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data() ?? <String, dynamic>{};

      _me = UserProfile.fromMap(
        uid,
        data,
        fallbackPhone: _auth.currentUser?.phoneNumber,
      );

      return _me!;
    });
  }

  /// Fetch the logged-in user's profile once
  Future<UserProfile?> getMe() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;

    _me = UserProfile.fromMap(
      uid,
      doc.data()!,
      fallbackPhone: _auth.currentUser?.phoneNumber,
    );

    return _me;
  }

  /// Explicit load and cache (optional)
  Future<void> loadCurrentProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return;

    _me = UserProfile.fromMap(
      uid,
      doc.data()!,
      fallbackPhone: _auth.currentUser?.phoneNumber,
    );
  }

  // ------------------------------------------------------------
  // PROFILE WRITES (🔥 CAMELCASE ONLY 🔥)
  // ------------------------------------------------------------

  /// Update display name
  Future<void> updateName(String name) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

 await _db.collection('users').doc(uid).set(
  {
    'display_name': trimmed,
    'updated_at': FieldValue.serverTimestamp(),
  },
  SetOptions(merge: true),
);


    // Keep FirebaseAuth displayName in sync
    try {
      await _auth.currentUser?.updateDisplayName(trimmed);
    } catch (_) {}
  }

  /// Update bio
  Future<void> updateBio(String bio) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

 await _db.collection('users').doc(uid).set(
  {
    'about': bio.trim(),
    'updated_at': FieldValue.serverTimestamp(),
  },
  SetOptions(merge: true),
);

  }

  /// ✅ Update avatar (CRITICAL FIX)
Future<void> updateAvatar(String url) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return;

  await _db.collection('users').doc(uid).set(
    {
      'avatar_url': url.trim(),               // ✅ snake_case
      'updated_at': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}


  // ------------------------------------------------------------
  // LINKS
  // ------------------------------------------------------------

  Future<void> addLink(String url) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).update({
      'links': FieldValue.arrayUnion([url]),
    });
  }

  Future<void> removeLink(String url) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).update({
      'links': FieldValue.arrayRemove([url]),
    });
  }

  // ------------------------------------------------------------
  // PUSH / ONESIGNAL (INTENTIONALLY SNAKE_CASE)
  // ------------------------------------------------------------

  /// Fetch OneSignal player IDs for a recipient user
  ///
  /// ⚠️ NOTE:
  /// These fields are intentionally snake_case because
  /// OneSignalService already uses this schema.
  Future<List<String>> fetchRecipientPlayerIds(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return [];

    final ids = <String>{};

    // single player id
    final single = data['player_id'];
    if (single is String && single.isNotEmpty) {
      ids.add(single);
    }

    // multiple player ids
    final arr = data['player_ids'];
    if (arr is List) {
      ids.addAll(
        arr.whereType<String>().where((e) => e.isNotEmpty),
      );
    }

    return ids.toList();
  }
}
