import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/models/chat_summary.dart';

class ChatsRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  ChatsRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  Stream<List<ChatSummary>> watchUserChats() {
  final uid = _auth.currentUser?.uid;

  if (uid == null || uid.isEmpty) {
    debugPrint('[ChatsRepo] No current user, returning []');
    return Stream.value(const <ChatSummary>[]);
  }

  final query = _db
      .collection('users')
      .doc(uid)
      .collection('chats')
      .orderBy('lastTime', descending: true)
      .limit(200);

  return query.snapshots().asyncMap((snap) async {
    debugPrint(
      '[ChatsRepo] 🔔 snapshot: docs=${snap.docs.length} fromCache=${snap.metadata.isFromCache}',
    );

    final List<ChatSummary> chats = [];

    for (final doc in snap.docs) {
      final data = doc.data();

      final members =
          (data['members'] as List?)?.map((e) => e.toString()).toList() ?? [];

      String otherUserId = data['otherUserId'] as String? ?? '';
      if (otherUserId.isEmpty && members.length == 2) {
        otherUserId =
            members.firstWhere((m) => m != uid, orElse: () => '');
      }

      // 🔁 BACKFILL other_phone_e164 (ONE TIME)
      if (data['other_phone_e164'] == null && otherUserId.isNotEmpty) {
        try {
          final userDoc = await _db
              .collection('users')
              .doc(otherUserId)
              .get();

          final phone = userDoc.data()?['phone_e164'];
          if (phone != null) {
            await doc.reference.update({
              'other_phone_e164': phone,
            });

            debugPrint(
              '[BACKFILL] chat=${doc.id} other_phone_e164=$phone',
            );
          }
        } catch (e) {
          debugPrint('[BACKFILL] failed for chat=${doc.id}: $e');
        }
      }

      chats.add(ChatSummary.fromDoc(doc));
    }

    return chats;
  });
}


  


}
