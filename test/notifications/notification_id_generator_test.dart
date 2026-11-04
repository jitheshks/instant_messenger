import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/notifications/data/notification_id_generator.dart';

void main() {
  group('NotificationIdGenerator Tests', () {
    test('Bounds and range constants match 31-bit signed positive integer range', () {
      expect(NotificationIdGenerator.minId, equals(0));
      expect(NotificationIdGenerator.maxId, equals(2147483647));
      expect(NotificationIdGenerator.maxId, equals(0x7FFFFFFF));

      // In-range boundaries
      expect(NotificationIdGenerator.isValidNotificationId(0), isTrue);
      expect(NotificationIdGenerator.isValidNotificationId(2147483647), isTrue);
      expect(NotificationIdGenerator.isValidNotificationId(100), isTrue);

      // Out-of-bounds checks
      expect(NotificationIdGenerator.isValidNotificationId(-1), isFalse);
      expect(NotificationIdGenerator.isValidNotificationId(-2147483648), isFalse);
      expect(NotificationIdGenerator.isValidNotificationId(2147483648), isFalse);
      expect(NotificationIdGenerator.isValidNotificationId(1793486076426856), isFalse);

      // Validation throws ArgumentError on out-of-bounds
      expect(() => NotificationIdGenerator.validateNotificationId(0), returnsNormally);
      expect(() => NotificationIdGenerator.validateNotificationId(2147483647), returnsNormally);
      expect(
        () => NotificationIdGenerator.validateNotificationId(1793486076426856),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NotificationIdGenerator.validateNotificationId(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Very large timestamp values always produce valid positive 31-bit IDs', () {
      // The exact microsecond timestamp from the runtime crash
      const crashingMicrosecondTimestamp = 1793486076426856;

      final id1 = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-uuid-1',
        messageId: null,
        fallbackTimestampMs: crashingMicrosecondTimestamp,
      );
      expect(id1, greaterThanOrEqualTo(0));
      expect(id1, lessThanOrEqualTo(2147483647));
      expect(NotificationIdGenerator.isValidNotificationId(id1), isTrue);

      // Maximum possible 64-bit integer
      const maxInt64 = 9223372036854775807;
      final id2 = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-uuid-1',
        messageId: null,
        fallbackTimestampMs: maxInt64,
      );
      expect(id2, greaterThanOrEqualTo(0));
      expect(id2, lessThanOrEqualTo(2147483647));
      expect(NotificationIdGenerator.isValidNotificationId(id2), isTrue);

      // Arbitrary large timestamps
      for (final ts in [
        1000000000000,
        1700000000000000,
        1793486076426856,
        5000000000000000,
      ]) {
        final id = NotificationIdGenerator.generateMessageNotificationId(
          chatId: 'test-chat',
          messageId: null,
          fallbackTimestampMs: ts,
        );
        expect(NotificationIdGenerator.isValidNotificationId(id), isTrue);
      }
    });

    test('UUID message IDs generate deterministic valid 31-bit IDs', () {
      final sampleUuids = [
        '3b290cb6-d3c2-4045-84dc-669c5e52c803',
        '099a184d-fa33-4375-bebe-08f97e20b60e',
        'c6b65389-408a-4467-bb1f-79836376878b',
        '70142ddd-32be-40e0-b1ce-97a1b958e3f4',
      ];

      for (final uuid in sampleUuids) {
        final id = NotificationIdGenerator.generateMessageNotificationId(
          chatId: 'chat-abc',
          messageId: uuid,
        );
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(2147483647));
        expect(NotificationIdGenerator.isValidNotificationId(id), isTrue);
      }
    });

    test('Repeated message IDs produce the identical notification ID (idempotent)', () {
      const messageId = '3b290cb6-d3c2-4045-84dc-669c5e52c803';

      final firstId = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: messageId,
      );
      final secondId = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: messageId,
      );
      final thirdIdWithWhitespace = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: '  $messageId  ',
      );

      expect(firstId, equals(secondId));
      expect(firstId, equals(thirdIdWithWhitespace));
    });

    test('Different message IDs produce distinct notification IDs', () {
      final idA = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: 'msg-0001',
      );
      final idB = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: 'msg-0002',
      );
      final idC = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: 'msg-0003',
      );

      expect(idA, isNot(equals(idB)));
      expect(idB, isNot(equals(idC)));
      expect(idA, isNot(equals(idC)));
    });

    test('Missing, null, or whitespace message IDs safely use fallback and stay in range', () {
      final idNull = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: null,
        fallbackTimestampMs: 123456789,
      );
      final idEmpty = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: '',
        fallbackTimestampMs: 123456789,
      );
      final idWhitespace = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: '   \n\t  ',
        fallbackTimestampMs: 123456789,
      );

      expect(NotificationIdGenerator.isValidNotificationId(idNull), isTrue);
      expect(NotificationIdGenerator.isValidNotificationId(idEmpty), isTrue);
      expect(NotificationIdGenerator.isValidNotificationId(idWhitespace), isTrue);

      // All three empty variants route to the same fallback key for consistent timestamp
      expect(idNull, equals(idEmpty));
      expect(idNull, equals(idWhitespace));
    });

    test('Group summary IDs are deterministic and distinct from message IDs', () {
      final summaryId1 = NotificationIdGenerator.generateGroupSummaryNotificationId('chat-1');
      final summaryId2 = NotificationIdGenerator.generateGroupSummaryNotificationId('chat-1');
      final summaryIdOther = NotificationIdGenerator.generateGroupSummaryNotificationId('chat-2');

      expect(summaryId1, equals(summaryId2));
      expect(summaryId1, isNot(equals(summaryIdOther)));
      expect(NotificationIdGenerator.isValidNotificationId(summaryId1), isTrue);
      expect(NotificationIdGenerator.isValidNotificationId(summaryIdOther), isTrue);

      // Summary ID does not collide with message ID for the same chatId string
      final messageId = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-1',
        messageId: 'chat-1',
      );
      expect(summaryId1, isNot(equals(messageId)));
    });

    test('FNV-1a 32-bit hash produces stable, deterministic values', () {
      expect(NotificationIdGenerator.fnv1a32(''), equals(0x811c9dc5));
      expect(NotificationIdGenerator.hashTo31Bit(''), equals(0x811c9dc5 & 0x7FFFFFFF));

      // Same string gives same hash every time
      final h1 = NotificationIdGenerator.fnv1a32('instant_messenger_test');
      final h2 = NotificationIdGenerator.fnv1a32('instant_messenger_test');
      expect(h1, equals(h2));
    });

    test('Repeated notifications for same message ID generate identical ID for updating in place', () {
      final id1 = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-A',
        messageId: 'msg-shared-uuid',
      );
      final id2 = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-A',
        messageId: 'msg-shared-uuid',
      );

      // Ensures repeated notifications update existing notification rather than creating duplicate
      expect(id1, equals(id2));

      // Different message in same chat generates distinct ID so it does not overwrite
      final id3 = NotificationIdGenerator.generateMessageNotificationId(
        chatId: 'chat-A',
        messageId: 'msg-other-uuid',
      );
      expect(id1, isNot(equals(id3)));
    });

    test('Cancellation lookup reproduces identical IDs for summary and message', () {
      const testChat = 'chat-cancel-test';
      const testMsg = 'msg-cancel-test';

      final originalMsgId = NotificationIdGenerator.generateMessageNotificationId(
        chatId: testChat,
        messageId: testMsg,
      );
      final cancelMsgId = NotificationIdGenerator.generateMessageNotificationId(
        chatId: testChat,
        messageId: testMsg,
      );
      expect(originalMsgId, equals(cancelMsgId));

      final originalSummaryId = NotificationIdGenerator.generateGroupSummaryNotificationId(testChat);
      final cancelSummaryId = NotificationIdGenerator.generateGroupSummaryNotificationId(testChat);
      expect(originalSummaryId, equals(cancelSummaryId));
    });
  });
}
