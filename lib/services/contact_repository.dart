import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:instant_messenger/models/contact_list_entry.dart';
import 'package:instant_messenger/services/acess_service_contact.dart';
import 'package:instant_messenger/utils/phone_format.dart';

class ContactsRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ContactsAccessService _access;

  ContactsRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    ContactsAccessService? access,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _access = access ?? ContactsAccessService();

  /// 🔹 Directory of all users (unfiltered)
  Stream<List<ContactListEntry>> watchDirectory({int limit = 1000}) {
    final me = _auth.currentUser?.uid;

    return _db
        .collection('users')
        // ✅ camelCase
        .orderBy('displayName')
        .limit(limit)
        .snapshots()
        .map(
          (qs) => qs.docs
              .where((d) => d.id != me)
              .map(
                (d) => ContactListEntry.fromFirestore(
                  docId: d.id,
                  data: d.data(),
                ),
              )
              .toList(),
        );
  }

  /// 🔹 Matched contacts (device contacts ∩ registered users)
  Stream<List<ContactListEntry>> watchMatched({
    String defaultIso2 = 'IN',
  }) async* {
    try {
      // 1️⃣ Read device contacts once
      final device = await _access.readPhoneContacts();
      debugPrint('[ContactsRepo] device entries: ${device.length}');

      // 2️⃣ Normalize numbers to E.164 format
      final pairs = <({String savedName, String? e164})>[];
      for (final d in device) {
        final e164 = await PhoneFormat.toE164(
          d.phoneRaw,
          iso2: defaultIso2,
        );
        pairs.add((savedName: d.savedName, e164: e164));
      }

      final e164Set =
          pairs.map((e) => e.e164).whereType<String>().toSet();

      debugPrint(
        '[ContactsRepo] normalized pairs=${pairs.length}, '
        'e164Set size=${e164Set.length}',
      );

      if (e164Set.isEmpty) {
        yield <ContactListEntry>[];
        return;
      }

      // 3️⃣ Stream users and match against device numbers
      yield* _db.collection('users').snapshots().map((qs) {
        final me = _auth.currentUser?.uid;
        final entries = <ContactListEntry>[];

        for (final d in qs.docs) {
          if (d.id == me) continue; // skip self

          final data = d.data();

          // ✅ camelCase
          final uPhone = (data['phone_e164'] as String?)?.trim();
          if (uPhone == null || !e164Set.contains(uPhone)) continue;

          // Find saved name from device contacts
          final saved = pairs.firstWhere(
            (p) => p.e164 == uPhone,
            orElse: () => (savedName: '', e164: uPhone),
          );

          final savedName = saved.savedName.trim();

          // WhatsApp-style priority
          final displayName =
              savedName.isNotEmpty ? savedName : uPhone;

          entries.add(
            ContactListEntry(
              uid: d.id,
              displayName: displayName,
              bio: (data['about'] as String?)?.trim(),
              avatarUrl: (data['avatarUrl'] as String?)?.trim(),
              phoneE164: uPhone,
            ),
          );
        }

        debugPrint(
          '[ContactsRepo] matched entries: ${entries.length}',
        );

        entries.sort(
          (a, b) => a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase()),
        );

        return entries;
      });
    } catch (e, st) {
      debugPrint('[ContactsRepo] watchMatched error: $e');
      debugPrintStack(stackTrace: st);
      yield <ContactListEntry>[];
    }
  }
}
