import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/contacts/data/acess_service_contact.dart';

void main() {
  group('ContactsAccessService Unit Tests (flutter_contacts 2.6.0)', () {
    test(
      'Returns parsed DeviceContact list when permission is granted',
      () async {
        final fakeContacts = [
          const Contact(
            displayName: 'Alice Smith',
            phones: [
              Phone(number: '+1 (555) 123-4567'),
              Phone(number: '555-9876'),
            ],
          ),
          const Contact(
            displayName: 'Bob Jones',
            phones: [Phone(number: '+44 20 7946 0991')],
          ),
        ];

        final service = ContactsAccessService(
          permissionCheck: () async => true,
          contactFetcher: () async => fakeContacts,
        );

        final result = await service.readPhoneContacts();

        expect(result, hasLength(3));
        expect(result[0].savedName, equals('Alice Smith'));
        expect(result[0].phoneRaw, equals('+15551234567'));

        expect(result[1].savedName, equals('Alice Smith'));
        expect(result[1].phoneRaw, equals('5559876'));

        expect(result[2].savedName, equals('Bob Jones'));
        expect(result[2].phoneRaw, equals('+442079460991'));
      },
    );

    test(
      'Returns empty list when permission is denied or not granted',
      () async {
        var fetcherCalled = false;
        final service = ContactsAccessService(
          permissionCheck: () async => false,
          contactFetcher: () async {
            fetcherCalled = true;
            return const [];
          },
        );

        final result = await service.readPhoneContacts();

        expect(result, isEmpty);
        expect(fetcherCalled, isFalse);
      },
    );

    test('Handles nullable or empty contact display names safely', () async {
      final fakeContacts = [
        const Contact(displayName: null, phones: [Phone(number: '+15550001')]),
        const Contact(
          displayName: '',
          phones: [Phone(number: '+15550002')],
        ),
      ];

      final service = ContactsAccessService(
        permissionCheck: () async => true,
        contactFetcher: () async => fakeContacts,
      );

      final result = await service.readPhoneContacts();

      expect(result, hasLength(2));
      expect(result[0].savedName, equals(''));
      expect(result[0].phoneRaw, equals('+15550001'));
      expect(result[1].savedName, equals(''));
      expect(result[1].phoneRaw, equals('+15550002'));
    });

    test(
      'Ignores contacts with missing, empty, or non-numeric phone numbers',
      () async {
        final fakeContacts = [
          const Contact(displayName: 'No Phones', phones: []),
          const Contact(
            displayName: 'Empty Phone',
            phones: [Phone(number: '')],
          ),
          const Contact(
            displayName: 'Non Numeric Only',
            phones: [Phone(number: '   --- () ')],
          ),
          const Contact(
            displayName: 'Valid Contact',
            phones: [Phone(number: '12345')],
          ),
        ];

        final service = ContactsAccessService(
          permissionCheck: () async => true,
          contactFetcher: () async => fakeContacts,
        );

        final result = await service.readPhoneContacts();

        expect(result, hasLength(1));
        expect(result[0].savedName, equals('Valid Contact'));
        expect(result[0].phoneRaw, equals('12345'));
      },
    );

    test(
      'Preserves digits and leading plus while stripping formatting characters',
      () async {
        final fakeContacts = [
          const Contact(
            displayName: 'Formatted International',
            phones: [Phone(number: '+91 (98765) 43210')],
          ),
          const Contact(
            displayName: 'Hyphenated Local',
            phones: [Phone(number: '080-1234-5678')],
          ),
        ];

        final service = ContactsAccessService(
          permissionCheck: () async => true,
          contactFetcher: () async => fakeContacts,
        );

        final result = await service.readPhoneContacts();

        expect(result, hasLength(2));
        expect(result[0].phoneRaw, equals('+919876543210'));
        expect(result[1].phoneRaw, equals('08012345678'));
      },
    );

    test(
      'Catches exceptions during permission check and returns empty list gracefully',
      () async {
        final service = ContactsAccessService(
          permissionCheck: () async =>
              throw Exception('Permission service crashed'),
          contactFetcher: () async => const [],
        );

        final result = await service.readPhoneContacts();
        expect(result, isEmpty);
      },
    );

    test(
      'Catches exceptions during contact fetch and returns empty list gracefully',
      () async {
        final service = ContactsAccessService(
          permissionCheck: () async => true,
          contactFetcher: () async =>
              throw Exception('Platform contact provider failure'),
        );

        final result = await service.readPhoneContacts();
        expect(result, isEmpty);
      },
    );
  });
}
