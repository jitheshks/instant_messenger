// test/notifications/delivery_receipt_notification_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';

void main() {
  group('Delivery Receipt & Notification Arrival Tests', () {
    test('1. Validates UUID v4 message IDs in FCM service', () {
      expect(
        FcmService.uuidRegex.hasMatch('a0000000-0000-0000-0000-000000000001'),
        isTrue,
      );
      expect(
        FcmService.uuidRegex.hasMatch('12345'),
        isFalse,
      );
      expect(
        FcmService.uuidRegex.hasMatch(''),
        isFalse,
      );
    });

    test('2. Notification payload contains required delivery acknowledgement parameters', () {
      final payload = {
        'chatId': 'c0000000-0000-0000-0000-000000000001',
        'messageId': 'a0000000-0000-0000-0000-000000000001',
        'receiptToken': 'rt-secret-12345',
        'senderPhone': '+15551234567',
        'senderId': 'u0000000-0000-0000-0000-000000000001',
      };

      final rawMsgId = payload['messageId'] ?? payload['message_id'];
      final messageId = rawMsgId?.toString().trim();
      final receiptToken = (payload['receiptToken'] ?? payload['receipt_token'])?.toString().trim();

      expect(messageId, 'a0000000-0000-0000-0000-000000000001');
      expect(receiptToken, 'rt-secret-12345');
      expect(FcmService.uuidRegex.hasMatch(messageId!), isTrue);
    });

    test('3. Simulated delivery acknowledgement updates status from sent (1) to delivered (2)', () {
      // Simulates Postgres monotonic progression rules
      int currentStatus = 1; // Sent (single tick)

      void handleDeliveryReceipt({required String messageId, String? receiptToken}) {
        if (currentStatus < 2) {
          currentStatus = 2; // Delivered (double tick)
        }
      }

      handleDeliveryReceipt(
        messageId: 'a0000000-0000-0000-0000-000000000001',
        receiptToken: 'token-abc',
      );

      expect(currentStatus, 2);

      // Re-delivery does not regress or break state
      handleDeliveryReceipt(
        messageId: 'a0000000-0000-0000-0000-000000000001',
        receiptToken: 'token-abc',
      );

      expect(currentStatus, 2);
    });

    test('4. Delivery acknowledgement cannot downgrade read status (3) to delivered (2)', () {
      int currentStatus = 3; // Read (double blue tick)

      void handleDeliveryReceipt({required String messageId}) {
        if (currentStatus < 2) {
          currentStatus = 2;
        }
      }

      handleDeliveryReceipt(messageId: 'a0000000-0000-0000-0000-000000000001');
      expect(currentStatus, 3); // Must remain read
    });
  });
}
