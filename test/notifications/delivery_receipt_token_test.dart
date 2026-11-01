import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simulates the server-side token validator and RPC rules implemented in
/// supabase/migrations/20261101000001_delivery_receipt_tokens.sql.
class MockDeliveryReceiptValidator {
  final Map<String, Map<String, dynamic>> messages = {};
  final Map<String, Map<String, dynamic>> tokens = {};
  final Set<String> chatMembers = {};

  void setupDirectChat({
    required String chatId,
    required String senderId,
    required String recipientId,
    required String messageId,
    int initialStatus = 1,
  }) {
    chatMembers.add('$chatId:$senderId');
    chatMembers.add('$chatId:$recipientId');
    messages[messageId] = {
      'id': messageId,
      'chat_id': chatId,
      'sender_id': senderId,
      'status': initialStatus,
    };
  }

  void issueToken({
    required String messageId,
    required String recipientId,
    required String token,
    required DateTime expiresAt,
  }) {
    tokens[token] = {
      'message_id': messageId,
      'recipient_id': recipientId,
      'token': token,
      'expires_at': expiresAt,
    };
  }

  int lastConsumedTokensCount = 0;

  /// Replicates public.acknowledge_delivery_token(p_message_id, p_receipt_token)
  bool acknowledgeDeliveryToken({
    required String? callerId,
    required String? messageId,
    required String? receiptToken,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();

    // 1. Caller authentication
    if (callerId == null || callerId.isEmpty) {
      throw Exception('42501 Unauthorized: caller must be authenticated');
    }

    if (messageId == null ||
        receiptToken == null ||
        receiptToken.trim().isEmpty) {
      lastConsumedTokensCount = 0;
      return false;
    }

    final cleanToken = receiptToken.trim();

    // 2. Atomic DELETE matching message_id, recipient_id, exact token, and unexpired
    // In PostgreSQL:
    // DELETE FROM public.message_delivery_receipt_tokens
    // WHERE message_id = p_message_id AND recipient_id = v_caller_id
    //   AND token = trim(p_receipt_token) AND expires_at > pg_catalog.clock_timestamp();
    // GET DIAGNOSTICS v_consumed_tokens = row_count;
    final tokenRecord = tokens[cleanToken];
    final bool matchesCriteria = tokenRecord != null &&
        tokenRecord['message_id'] == messageId &&
        tokenRecord['recipient_id'] == callerId &&
        !now.isAfter(tokenRecord['expires_at'] as DateTime);

    if (!matchesCriteria) {
      lastConsumedTokensCount = 0;
      return false; // Zero rows deleted, abort without updating message
    }

    // Atomically consume token (ROW_COUNT = 1)
    tokens.remove(cleanToken);
    lastConsumedTokensCount = 1;

    // 4. Message existence & conversation membership check
    final msg = messages[messageId];
    if (msg == null) return false;

    final chatId = msg['chat_id'] as String;
    final senderId = msg['sender_id'] as String;

    if (!chatMembers.contains('$chatId:$callerId')) return false;

    // 5. Authorship boundary: sender cannot self-acknowledge
    if (senderId == callerId) return false;

    // 6. Monotonic forward-only check: status < 2
    final currentStatus = msg['status'] as int;
    if (currentStatus < 2) {
      msg['status'] = 2; // Advance to delivered only
    }

    return true;
  }
}

void main() {
  group('Delivery Receipt Token & Backend Acknowledgment Rules', () {
    late MockDeliveryReceiptValidator validator;
    const senderId = 'sender-uuid-001';
    const recipientId = 'recipient-uuid-002';
    const chatId = 'chat-uuid-100';
    const messageId = 'msg-uuid-500';
    const validToken = 'token-secret-abc-123';

    setUp(() {
      validator = MockDeliveryReceiptValidator();
      validator.setupDirectChat(
        chatId: chatId,
        senderId: senderId,
        recipientId: recipientId,
        messageId: messageId,
        initialStatus: 1, // Sent
      );
    });

    test('Valid token from recipient successfully promotes message to status 2 (Delivered)', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isTrue);
      expect(validator.messages[messageId]!['status'], equals(2));
    });

    test('Sender cannot self-acknowledge their own message (Authorship Guard)', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: senderId, // Incorrectly issued to sender
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: senderId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isFalse);
      expect(validator.messages[messageId]!['status'], equals(1));
    });

    test('Expired token is rejected and leaves status unchanged', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 10)), // Expired
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isFalse);
      expect(validator.messages[messageId]!['status'], equals(1));
    });

    test('Token is single-use and cannot be replayed', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      // First attempt succeeds
      final first = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );
      expect(first, isTrue);

      // Replay attempt fails because token was consumed
      final replay = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );
      expect(replay, isFalse);
    });

    test('Token issued to a different recipient cannot be used by third party', () {
      const imposterId = 'imposter-uuid-999';
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: imposterId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isFalse);
      expect(validator.messages[messageId]!['status'], equals(1));
    });

    test('Unauthenticated caller throws 42501 Unauthorized', () {
      expect(
        () => validator.acknowledgeDeliveryToken(
          callerId: null,
          messageId: messageId,
          receiptToken: validToken,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Delivery acknowledgment NEVER marks message as read (status 3)', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(validator.messages[messageId]!['status'], equals(2));
      expect(validator.messages[messageId]!['status'], isNot(equals(3)));
    });

    test('Monotonic protection: already read message (status 3) does not regress to 2', () {
      validator.messages[messageId]!['status'] = 3; // Already read

      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isTrue);
      expect(validator.messages[messageId]!['status'], equals(3)); // Stays 3
    });

    test('Valid token consumes exactly one row (ROW_COUNT == 1)', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );

      expect(success, isTrue);
      expect(validator.lastConsumedTokensCount, equals(1));
    });

    test('Invalid token returns false and consumes zero rows (ROW_COUNT == 0)', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final success = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: 'completely-bogus-token-string',
      );

      expect(success, isFalse);
      expect(validator.lastConsumedTokensCount, equals(0));
      expect(validator.messages[messageId]!['status'], equals(1)); // Message status unchanged
    });

    test('Failed token consumption never updates the message', () {
      validator.messages[messageId]!['status'] = 1;

      // 1. Expired token
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: 'expired-token',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final r1 = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: 'expired-token',
      );
      expect(r1, isFalse);
      expect(validator.lastConsumedTokensCount, equals(0));
      expect(validator.messages[messageId]!['status'], equals(1));

      // 2. Wrong recipient
      validator.issueToken(
        messageId: messageId,
        recipientId: 'other-user',
        token: 'other-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final r2 = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: 'other-token',
      );
      expect(r2, isFalse);
      expect(validator.lastConsumedTokensCount, equals(0));
      expect(validator.messages[messageId]!['status'], equals(1));
    });

    test('Concurrent requests using the same token: only one may successfully consume it', () {
      validator.issueToken(
        messageId: messageId,
        recipientId: recipientId,
        token: validToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      // Simulate Request 1 executing atomic DELETE
      final req1 = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );
      expect(req1, isTrue);
      expect(validator.lastConsumedTokensCount, equals(1));
      expect(validator.messages[messageId]!['status'], equals(2));

      // Simulate Request 2 executing concurrent/subsequent DELETE with same token
      // Token is already gone, so DELETE yields ROW_COUNT == 0
      final req2 = validator.acknowledgeDeliveryToken(
        callerId: recipientId,
        messageId: messageId,
        receiptToken: validToken,
      );
      expect(req2, isFalse);
      expect(validator.lastConsumedTokensCount, equals(0));
      expect(validator.messages[messageId]!['status'], equals(2));
    });
  });

  group('Native Android Extension Manifest & Proguard Verification', () {
    test('AndroidManifest.xml contains OneSignal NotificationServiceExtension declaration', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();
      expect(
        content.contains('android:name="com.onesignal.NotificationServiceExtension"'),
        isTrue,
        reason: 'Manifest must register com.onesignal.NotificationServiceExtension meta-data',
      );
      expect(
        content.contains('android:value="com.example.instant_messenger.InstantMessengerNotificationExtension"'),
        isTrue,
        reason: 'Meta-data value must point to InstantMessengerNotificationExtension',
      );
    });

    test('proguard-rules.pro preserves native notification service extension class and interfaces', () {
      final proguardFile = File('android/app/proguard-rules.pro');
      expect(proguardFile.existsSync(), isTrue);

      final content = proguardFile.readAsStringSync();
      expect(
        content.contains('-keep class com.example.instant_messenger.InstantMessengerNotificationExtension { *; }'),
        isTrue,
        reason: 'Proguard must retain InstantMessengerNotificationExtension to prevent R8 stripping in release',
      );
      expect(
        content.contains('-keep interface com.onesignal.notifications.INotificationServiceExtension { *; }'),
        isTrue,
        reason: 'Proguard must retain INotificationServiceExtension interface',
      );
    });

    test('InstantMessengerNotificationExtension.kt exists with correct package and interface', () {
      final ktFile = File('android/app/src/main/kotlin/com/example/instant_messenger/InstantMessengerNotificationExtension.kt');
      expect(ktFile.existsSync(), isTrue);

      final content = ktFile.readAsStringSync();
      expect(content.contains('package com.example.instant_messenger'), isTrue);
      expect(content.contains('class InstantMessengerNotificationExtension : INotificationServiceExtension'), isTrue);
      expect(content.contains('override fun onNotificationReceived(event: INotificationReceivedEvent)'), isTrue);
      expect(content.contains('acknowledge_delivery_token'), isTrue);
      expect(content.contains('@Keep'), isTrue);
    });
  });

  group('SupabaseConfig SharedPreferences Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('SupabaseConfig.initialize writes supabase_url and supabase_anon_key to SharedPreferences', () async {
      final config = AppConfig(
        supabaseUrl: 'https://test-project.supabase.co',
        supabasePublishableKey: 'test-anon-key-12345',
        oneSignalAppId: 'onesignal-app-id-test',
      );

      SupabaseConfig.setInitializerForTesting(({required anonKey, required url}) async {
        // Mock successful initialization without live network
      });

      await SupabaseConfig.initialize(config);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('supabase_url'), equals('https://test-project.supabase.co'));
      expect(prefs.getString('supabase_anon_key'), equals('test-anon-key-12345'));
    });
  });
}
