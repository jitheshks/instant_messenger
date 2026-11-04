// test/contacts/contact_persistence_and_resolution_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';

void main() {
  group('Contact Persistence and Resolution Tests', () {
    const peerPhone = '+919645905577';
    const peerUid = 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc';
    const savedName = 'User A-1';

    test('1. ContactListEntry serializes to JSON and deserializes identically', () {
      const entry = ContactListEntry(
        uid: peerUid,
        displayName: savedName,
        savedName: savedName,
        phoneE164: peerPhone,
        avatarUrl: 'https://example.com/avatar.jpg',
        bio: 'Hey there!',
        isSaved: true,
      );

      final json = entry.toJson();
      final restored = ContactListEntry.fromJson(json);

      expect(restored.uid, equals(peerUid));
      expect(restored.displayName, equals(savedName));
      expect(restored.savedName, equals(savedName));
      expect(restored.phoneE164, equals(peerPhone));
      expect(restored.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(restored.bio, equals('Hey there!'));
      expect(restored.isSaved, isTrue);
    });

    test('2. Resolves saved contact name consistently across phone formats without opening contacts screen', () {
      final contacts = [
        const ContactListEntry(
          uid: peerUid,
          displayName: savedName,
          savedName: savedName,
          phoneE164: peerPhone,
          isSaved: true,
        ),
      ];

      // Exact E.164
      expect(
        ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919645905577',
          contacts: contacts,
        ),
        equals('User A-1'),
      );

      // National format with spaces
      expect(
        ContactIdentityResolver.resolveIdentity(
          phoneE164: '+91 96459 05577',
          contacts: contacts,
        ),
        equals('User A-1'),
      );

      // 10-digit national number
      expect(
        ContactIdentityResolver.resolveIdentity(
          phoneE164: '9645905577',
          contacts: contacts,
        ),
        equals('User A-1'),
      );

      // Leading 0 trunk format
      expect(
        ContactIdentityResolver.resolveIdentity(
          phoneE164: '09645905577',
          contacts: contacts,
        ),
        equals('User A-1'),
      );
    });

    test('3. Resolves saved contact by userId when phone is absent or null', () {
      final contacts = [
        const ContactListEntry(
          uid: peerUid,
          displayName: savedName,
          savedName: savedName,
          phoneE164: peerPhone,
          isSaved: true,
        ),
      ];

      final resolved = ContactIdentityResolver.resolveIdentity(
        phoneE164: null,
        userId: peerUid,
        contacts: contacts,
        fallback: 'Chat',
      );

      expect(resolved, equals('User A-1'));
    });

    test('4. Unsaved contact falls back to phone number, never profile display_name', () {
      final contacts = [
        const ContactListEntry(
          uid: 'unsaved_peer_id',
          displayName: 'jithesh', // remote profile display_name
          savedName: null,
          phoneE164: '+919999988888',
          isSaved: false, // NOT saved in address book
        ),
      ];

      final resolved = ContactIdentityResolver.resolveIdentity(
        phoneE164: '+919999988888',
        contacts: contacts,
      );

      // Per WhatsApp privacy rules, unsaved contacts display the phone number, not their chosen profile name
      expect(resolved, equals('+919999988888'));
      expect(resolved, isNot(equals('jithesh')));
    });

    test('5. Missing contact and missing phone gracefully returns neutral fallback', () {
      final resolved = ContactIdentityResolver.resolveIdentity(
        phoneE164: null,
        userId: null,
        contacts: const [],
        fallback: 'New message',
      );

      expect(resolved, equals('New message'));
    });
  });
}
