import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:instant_messenger/services/local_cache.dart';
import 'package:instant_messenger/services/message_cache.dart';
import '../utils/phone_format.dart';

enum NextRoute { editName, profile, chats }

class UserBootstrap {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  MessageCache? messageCache;

  UserBootstrap({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  // ------------------------------------------------------------
  // ENSURE USER PROFILE EXISTS (NON-DESTRUCTIVE)
  // ------------------------------------------------------------
  Future<void> _ensureProfileDoc() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();

    final e164 =
        await PhoneFormat.toE164(user.phoneNumber ?? '', iso2: 'IN');

    if (!snap.exists) {
      await ref.set({
        'phone_e164': (e164 ?? '').trim(),
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (e164 != null) {
      final stored = (snap.data()?['phone_e164'] as String?)?.trim();
      if (stored != e164) {
        await ref.update({'phone_e164': e164.trim()});
      }
    }
  }

// ------------------------------------------------------------
// BOOTSTRAP FLOW (WHATSAPP STYLE) — FIXED
// ------------------------------------------------------------
Future<NextRoute> bootstrap() async {
  final user = _auth.currentUser;
  if (user == null) return NextRoute.profile;

  // 1️⃣ Ensure user doc exists
  await _ensureProfileDoc();

  // 2️⃣ Open message cache once
  messageCache ??= await MessageCache.open(uid: user.uid);

  // 🔥 3️⃣ LOCAL CACHE FIRST (SOURCE OF TRUTH)
  final cachedName = LocalCache.displayName;
  debugPrint('[Bootstrap] cached display_name="$cachedName"');

  if (cachedName != null && cachedName.isNotEmpty) {
    // 🔁 Background Firestore sync (non-blocking)
    _syncProfileFromFirestore(user.uid);
    return NextRoute.chats;
  }

  // 🔁 4️⃣ FIRESTORE FALLBACK (ONLY IF LOCAL EMPTY)
  final doc = await _db.collection('users').doc(user.uid).get();
  final raw = doc.data()?['display_name'];

  final name =
      (raw is String && raw.trim().isNotEmpty) ? raw.trim() : null;

  debugPrint('[Bootstrap] firestore display_name="$name"');

  if (name == null) {
    return NextRoute.editName;
  }

  // 🔐 5️⃣ SAVE INTO LOCAL CACHE
  await LocalCache.setProfile(displayName: name);

  return NextRoute.chats;
}


 // ------------------------------------------------------------
// UPDATE DISPLAY NAME (LOCAL → FIRESTORE)
// ------------------------------------------------------------
Future<void> setDisplayName(String displayName) async {
  final user = _auth.currentUser;
  if (user == null) throw Exception('Not signed in');

  final trimmed = displayName.trim();

  // 🔥 LOCAL FIRST (PREVENTS COLD BOOT RACE)
  await LocalCache.setProfile(displayName: trimmed);

  // 🔁 FIRESTORE
  await _db.collection('users').doc(user.uid).set({
    'display_name': trimmed,
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  try {
    await user.updateDisplayName(trimmed);
  } catch (_) {}
}


  // ------------------------------------------------------------
// BACKGROUND PROFILE SYNC (OPTIONAL BUT RECOMMENDED)
// ------------------------------------------------------------
Future<void> _syncProfileFromFirestore(String uid) async {
  try {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return;

    await LocalCache.setProfile(
      displayName: data['display_name'],
      avatarUrl: data['avatar_url'],
      phoneE164: data['phone_e164'],
    );

    debugPrint('[Bootstrap] profile synced from Firestore');
  } catch (e) {
    debugPrint('[Bootstrap] profile sync failed: $e');
  }
}

}
