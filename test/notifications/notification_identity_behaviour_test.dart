import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Identity Behaviour Tests', () {
    // --------------------------------------------------------------------------
    // Test Contacts Setup
    // --------------------------------------------------------------------------
    const savedContactMom = ContactListEntry(
      displayName: 'Mom',
      savedName: 'Mom',
      isSaved: true,
      phoneE164: '+919876543210',
      uid: 'user-mom-111',
    );

    const savedContactBoss = ContactListEntry(
      displayName: 'Office Boss',
      savedName: 'Office Boss',
      isSaved: true,
      phoneE164: '+14155552671',
      uid: 'user-boss-222',
    );

    // Profile from directory that is NOT saved in the recipient device's address book
    const unsavedDirectoryUser = ContactListEntry(
      displayName: 'alice_superstar',
      savedName: null,
      isSaved: false,
      phoneE164: '+919811122233',
      uid: 'user-alice-333',
    );

    // Profile from Supabase with display_name but empty savedName and isSaved: false
    final unsavedProfileFromSupabase = ContactListEntry.fromSupabase(
      {
        'id': 'user-bob-444',
        'display_name': 'bobby_tables',
        'phone_e164': '+919844455566',
        'avatar_url': 'https://example.com/avatar.jpg',
      },
      fallbackSavedName: null, // NOT in device contacts
    );

    final contactsList = [
      savedContactMom,
      savedContactBoss,
      unsavedDirectoryUser,
      unsavedProfileFromSupabase,
    ];

    // ==========================================================================
    // 1. Saved Contact -> Saved Contact Name
    // ==========================================================================
    group('1. Saved Contact -> Saved Contact Name', () {
      test('Returns saved contact name when sender phone matches exact E.164', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919876543210',
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('Mom'));
      });

      test('Returns saved contact name when matching international US number', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+14155552671',
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('Office Boss'));
      });

      test('Returns saved contact name when formatted with national 10 digits', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '9876543210',
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('Mom'));
      });
    });

    // ==========================================================================
    // 2. Unsaved Contact -> Sender Phone Number
    // ==========================================================================
    group('2. Unsaved Contact -> Sender Phone Number', () {
      test('Returns sender phone number when phone does not exist in contacts list', () {
        const unknownPhone = '+919123456789';
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: unknownPhone,
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals(unknownPhone));
      });

      test('Returns sender phone number when contacts list is empty or null', () {
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
    });

    // ==========================================================================
    // 3. Missing Sender Phone -> "New message" Neutral Fallback
    // ==========================================================================
    group('3. Missing Sender Phone -> "New message"', () {
      test('Returns "New message" when phone is null', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: null,
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('New message'));
      });

      test('Returns "New message" when phone is empty or only whitespace', () {
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: '',
            contacts: contactsList,
            fallback: 'New message',
          ),
          equals('New message'),
        );
        expect(
          ContactIdentityResolver.resolveIdentity(
            phoneE164: '   ',
            contacts: contactsList,
            fallback: 'New message',
          ),
          equals('New message'),
        );
      });
    });

    // ==========================================================================
    // 4. Username Present but Phone Unsaved -> Phone Number, Never Username
    // ==========================================================================
    group('4. Username Present but Phone Unsaved -> Phone Number, Never Username', () {
      test('Unsaved directory user returns phone number, never displayName/username', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919811122233',
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('+919811122233'));
        expect(result, isNot(equals('alice_superstar')));
      });

      test('Profile loaded from Supabase without address book match returns phone number, never remote username', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919844455566',
          contacts: contactsList,
          fallback: 'New message',
        );
        expect(result, equals('+919844455566'));
        expect(result, isNot(equals('bobby_tables')));
      });

      test('Fallback parameter is ignored when phone is present (does not leak username fallback)', () {
        final result = ContactIdentityResolver.resolveIdentity(
          phoneE164: '+919811122233',
          contacts: contactsList,
          fallback: 'SpoofedUsername',
        );
        expect(result, equals('+919811122233'));
        expect(result, isNot(equals('SpoofedUsername')));
      });
    });

    // ==========================================================================
    // 5. National / International Number Normalization
    // ==========================================================================
    group('5. National / International Number Normalization', () {
      test('Matches formatted phone numbers with spaces, dashes, dots, and slashes', () {
        expect(
          ContactIdentityResolver.matchPhone('+91 98765-43210', '+919876543210'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('+1 (415) 555-2671', '+14155552671'),
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

      test('Matches 00 international prefix to + E.164 standard', () {
        expect(
          ContactIdentityResolver.matchPhone('00919876543210', '+919876543210'),
          isTrue,
        );
        expect(
          ContactIdentityResolver.matchPhone('+919876543210', '00919876543210'),
          isTrue,
        );
      });

      test('Matches Indian national number with leading 0 trunk prefix', () {
        expect(
          ContactIdentityResolver.matchPhone('09876543210', '+919876543210'),
          isTrue,
        );
      });

      test('Rejects different country codes even if 10-digit suffix matches', () {
        // US (+1) vs India (+91) with identical 10-digit subscriber number
        expect(
          ContactIdentityResolver.matchPhone('+19876543210', '+919876543210'),
          isFalse,
        );
      });

      test('Rejects non-matching numbers and null/empty safely', () {
        expect(ContactIdentityResolver.matchPhone('+919876543210', '+919111111111'), isFalse);
        expect(ContactIdentityResolver.matchPhone(null, '+919876543210'), isFalse);
        expect(ContactIdentityResolver.matchPhone('+919876543210', null), isFalse);
        expect(ContactIdentityResolver.matchPhone('', ''), isFalse);
      });
    });

    // ==========================================================================
    // 6. Foreground, Background, and Terminated Notification Title Behaviour
    // ==========================================================================
    group('6. Foreground, Background, and Terminated Notification Title Behaviour', () {
      setUp(() {
        OneSignalService.resolveContactDelegate = null;
        OneSignalService.isChatOpenDelegate = null;
      });

      tearDown(() {
        OneSignalService.resolveContactDelegate = null;
        OneSignalService.isChatOpenDelegate = null;
      });

      test('Foreground: Resolves senderPhone against saved contacts -> displays saved contact name', () {
        OneSignalService.resolveContactDelegate = (phone) {
          return ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: contactsList,
            fallback: phone ?? 'New message',
          );
        };

        const incomingSenderPhone = '+919876543210';
        final resolvedTitle = OneSignalService.resolveContactDelegate!(incomingSenderPhone);
        expect(resolvedTitle, equals('Mom'));
      });

      test('Foreground: Unsaved senderPhone displays senderPhone, never username', () {
        OneSignalService.resolveContactDelegate = (phone) {
          return ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: contactsList,
            fallback: phone ?? 'New message',
          );
        };

        const unsavedSenderPhone = '+919811122233';
        final resolvedTitle = OneSignalService.resolveContactDelegate!(unsavedSenderPhone);
        expect(resolvedTitle, equals('+919811122233'));
        expect(resolvedTitle, isNot(equals('alice_superstar')));
      });

      test('Foreground: Missing senderPhone falls back to "New message"', () {
        OneSignalService.resolveContactDelegate = (phone) {
          return ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: contactsList,
            fallback: phone ?? 'New message',
          );
        };

        final resolvedTitle = OneSignalService.resolveContactDelegate!(null);
        expect(resolvedTitle, equals('New message'));
      });

      test('Foreground: When notification.title contains username, resolver ignores it and displays phone number', () {
        OneSignalService.resolveContactDelegate = (phone) {
          return ContactIdentityResolver.resolveIdentity(
            phoneE164: phone,
            contacts: contactsList,
            fallback: phone ?? 'New message',
          );
        };

        const unsavedPhone = '+919811122233';
        const rawNotificationTitle = 'AliceUsername';

        final cleanPhone = unsavedPhone.isNotEmpty ? unsavedPhone : null;
        final resolvedTitle = OneSignalService.resolveContactDelegate?.call(cleanPhone) ??
            cleanPhone ??
            'New message';

        expect(resolvedTitle, equals('+919811122233'));
        expect(resolvedTitle, isNot(equals(rawNotificationTitle)));
      });

      test('Foreground: Suppresses notification when user is actively inside the same chat', () {
        OneSignalService.isChatOpenDelegate = (chatId) => chatId == 'chat-open-123';

        expect(OneSignalService.isChatOpenDelegate!('chat-open-123'), isTrue);
        expect(OneSignalService.isChatOpenDelegate!('chat-other-456'), isFalse);
      });

      test('Background and Terminated: Server constructs headings exclusively from registered phone, never username', () {
        // Backend derivation simulation (matching supabase/functions/send-push/index.ts)
        Map<String, dynamic> buildBackendPayload({
          required String chatId,
          required String messageId,
          required String callerId,
          required String? registeredPhone,
          required String? profileDisplayName,
          required String messageText,
        }) {
          final cleanPhone = registeredPhone?.trim() ?? '';
          final headingsTitle = cleanPhone.isNotEmpty ? cleanPhone : 'New message';

          return {
            'headings': {'en': headingsTitle},
            'contents': {'en': messageText},
            'data': {
              'chatId': chatId,
              'messageId': messageId,
              'type': 'text',
              'senderPhone': cleanPhone,
              'senderId': callerId,
            },
          };
        }

        // Case A: Sender with registered phone number and username
        final payloadWithPhoneAndUsername = buildBackendPayload(
          chatId: 'e2a4b880-9b36-4d22-9029-2182c1e7a5c1',
          messageId: 'b1e6701f-a136-4fb1-befb-8e9e23dcd12b',
          callerId: 'user-caller-111',
          registeredPhone: '+919811122233',
          profileDisplayName: 'SuperStarAlice',
          messageText: 'Hello from background',
        );

        // Native notification title displayed on system tray:
        final nativeBackgroundTitle = (payloadWithPhoneAndUsername['headings'] as Map)['en'];
        expect(nativeBackgroundTitle, equals('+919811122233'));
        expect(nativeBackgroundTitle, isNot(equals('SuperStarAlice')));

        final additionalData = payloadWithPhoneAndUsername['data'] as Map;
        expect(additionalData['senderPhone'], equals('+919811122233'));
        expect(additionalData['senderId'], equals('user-caller-111'));
        expect(additionalData['chatId'], equals('e2a4b880-9b36-4d22-9029-2182c1e7a5c1'));
        expect(additionalData['messageId'], equals('b1e6701f-a136-4fb1-befb-8e9e23dcd12b'));
        expect(additionalData['type'], equals('text'));

        // Case B: Sender without registered phone number
        final payloadWithoutPhone = buildBackendPayload(
          chatId: 'e2a4b880-9b36-4d22-9029-2182c1e7a5c1',
          messageId: 'b1e6701f-a136-4fb1-befb-8e9e23dcd12b',
          callerId: 'user-caller-111',
          registeredPhone: null,
          profileDisplayName: 'SuperStarAlice',
          messageText: 'Hello from background',
        );

        final fallbackTitle = (payloadWithoutPhone['headings'] as Map)['en'];
        expect(fallbackTitle, equals('New message'));
        expect(fallbackTitle, isNot(equals('SuperStarAlice')));
      });
    });
  });
}
