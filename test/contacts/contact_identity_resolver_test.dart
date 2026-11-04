import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';

void main() {
  group('ContactIdentityResolver Tests', () {
    const contactAmal = ContactListEntry(
      displayName: 'Amal',
      savedName: 'Amal',
      isSaved: true,
      phoneE164: '+919876543210',
      uid: 'user-amal',
    );

    const contactBob = ContactListEntry(
      displayName: 'Bob Work',
      savedName: 'Bob Work',
      isSaved: true,
      phoneE164: '+14155552671',
      uid: 'user-bob',
    );

    const unsavedProfileUser = ContactListEntry(
      displayName: 'alice_wonderland',
      savedName: null,
      isSaved: false,
      phoneE164: '+919811122233',
      uid: 'user-alice-unsaved',
    );

    final contacts = [contactAmal, contactBob, unsavedProfileUser];

    group('matchPhone', () {
      test('matches identical E.164 phone numbers', () {
        expect(
          ContactIdentityResolver.matchPhone('+919876543210', '+919876543210'),
          isTrue,
        );
      });

      test('matches formatted phone numbers with spaces, dashes, dots, slashes, or parentheses', () {
        expect(
          ContactIdentityResolver.matchPhone('+91 98765-43210', '+919876543210'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('(415) 555-2671', '+14155552671'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('415.555.2671', '+14155552671'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('+91/9876543210', '+919876543210'),
          isTrue,
        );
      });

      test('matches 00 international prefix to + E.164 prefix', () {
        expect(
          ContactIdentityResolver.matchPhone('00919876543210', '+919876543210'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('+919876543210', '00919876543210'),
          isTrue,
        );
      });

      test('matches 10-digit national number with international E.164 number', () {
        expect(
          ContactIdentityResolver.matchPhone('9876543210', '+919876543210'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('+919876543210', '9876543210'),
          isTrue,
        );
      });

      test('matches Indian national number with leading 0 trunk prefix to E.164 number', () {
        expect(
          ContactIdentityResolver.matchPhone('09876543210', '+919876543210'),
          isTrue,
        );
      });

      test('returns false for different country codes even if 10-digit suffix matches', () {
        expect(
          ContactIdentityResolver.matchPhone('+19876543210', '+919876543210'),
          isFalse,
        );
      });

      test('returns false for completely different phone numbers', () {
        expect(
          ContactIdentityResolver.matchPhone('+919876543210', '+919123456789'),
          isFalse,
        );
      });

      test('returns false for null or empty strings', () {
        expect(ContactIdentityResolver.matchPhone(null, '+919876543210'), isFalse);
        expect(ContactIdentityResolver.matchPhone('+919876543210', null), isFalse);
        expect(ContactIdentityResolver.matchPhone('', ''), isFalse);
      });
    });

    group('resolveIdentity', () {
      test('Priority 1: returns saved contact name when sender phone matches saved contact', () {
        final name = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919876543210',
          contacts: contacts,
          fallback: 'New message',
        );
        expect(name, equals('Amal'));
      });

      test('Priority 1: returns saved contact name when matching national 10-digit format', () {
        final name = ContactIdentityResolver.resolveIdentity(
          phoneE164: '9876543210',
          contacts: contacts,
          fallback: 'New message',
        );
        expect(name, equals('Amal'));
      });

      test('Priority 2: returns phone number when no saved contact matches', () {
        const unknownPhone = '+919999988888';
        final name = ContactIdentityResolver.resolveIdentity(
          phoneE164: unknownPhone,
          contacts: contacts,
          fallback: 'New message',
        );
        expect(name, equals(unknownPhone));
      });

      test('Priority 2: returns phone number when contacts list is empty or null', () {
        const phone = '+919876543210';
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: [],
            fallback: 'New message',
          ),
          equals(phone),
        );
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: null,
            fallback: 'New message',
          ),
          equals(phone),
        );
      });

      test('Priority 3: username present but phone unsaved -> returns phone number, never username', () {
        final resolved = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919811122233',
          contacts: contacts,
          fallback: 'New message',
        );
        expect(resolved, equals('+919811122233'));
        expect(resolved, isNot(equals('alice_wonderland')));
      });

      test('Priority 4: returns neutral fallback "New message" when phone number is null or empty', () {
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: null,
            contacts: contacts,
            fallback: 'New message',
          ),
          equals('New message'),
        );
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: '   ',
            contacts: contacts,
            fallback: 'New message',
          ),
          equals('New message'),
        );
      });
    });
  });
}
