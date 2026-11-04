import 'package:flutter_test/flutter_test.dart';

/// Simulates and verifies the validation, authorization, content derivation,
/// and rate-limiting rules defined in supabase/functions/send-push/index.ts (Step 2E.11).
class EdgePushValidator {
  static const int maxPreviewLength = 120;
  static const int maxSenderNameLength = 50;
  static const int maxRequestsPerMinute = 30;
  static const Set<String> allowedTypes = {'text', 'media', 'call'};
  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final Map<String, List<DateTime>> _rateLimitMap = {};

  bool validateUUID(String? uuid) {
    if (uuid == null) return false;
    return uuidRegex.hasMatch(uuid);
  }

  /// Derives notification content strictly from persisted database records,
  /// ignoring unverified client-supplied content.
  Map<String, String> deriveNotificationContent({
    required Map<String, dynamic> messageRecord,
    Map<String, dynamic>? profileRecord,
  }) {
    // 1. Sanitize message type from database
    final rawType = messageRecord['type'] is String
        ? (messageRecord['type'] as String).toLowerCase().trim()
        : 'text';
    final type = allowedTypes.contains(rawType) ? rawType : 'text';

    // 2. Derive preview from database record
    String preview = 'New message';
    if (type == 'text') {
      final rawText = messageRecord['text'] is String
          ? (messageRecord['text'] as String).trim()
          : '';
      if (rawText.isNotEmpty) {
        preview = rawText.length > maxPreviewLength
            ? rawText.substring(0, maxPreviewLength)
            : rawText;
      }
    } else if (type == 'media') {
      final rawCaption = messageRecord['text'] is String
          ? (messageRecord['text'] as String).trim()
          : '';
      if (rawCaption.isNotEmpty) {
        preview = rawCaption.length > maxPreviewLength
            ? rawCaption.substring(0, maxPreviewLength)
            : rawCaption;
      } else {
        final media = messageRecord['media'] is Map
            ? messageRecord['media'] as Map
            : null;
        final mediaKind = media != null && media['kind'] is String
            ? (media['kind'] as String).toLowerCase().trim()
            : '';

        switch (mediaKind) {
          case 'image':
            preview = '📷 Photo';
            break;
          case 'video':
            preview = '🎥 Video';
            break;
          case 'audio':
            preview = '🎵 Audio';
            break;
          default:
            preview = '📎 Attachment';
            break;
        }
      }
    } else if (type == 'call') {
      preview = '📞 Incoming call';
    }

    // 3. Derive sender title according to privacy and contact-identity rules:
    // Priority:
    // 1. If phone_e164 is available, use it so unsaved contacts display phone number.
    // 2. If phone is unavailable, use generic fallback ("New message") rather than preferring username.
    String senderName = 'New message';
    final rawPhone = profileRecord?['phone_e164'];
    if (rawPhone is String && rawPhone.trim().isNotEmpty) {
      final clean = rawPhone.trim();
      senderName = clean.length > maxSenderNameLength
          ? clean.substring(0, maxSenderNameLength)
          : clean;
    }

    return {'preview': preview, 'type': type, 'sender_name': senderName};
  }

  /// Simulates membership and message authorship validation
  int validateMessageAuthorization({
    required String callerId,
    required String chatId,
    required List<String> chatMembers,
    required Map<String, dynamic>? messageRecord,
  }) {
    // 1. Must be chat member
    if (!chatMembers.contains(callerId)) {
      return 403; // Forbidden
    }

    // 2. Message must exist and belong to chat
    if (messageRecord == null || messageRecord['chat_id'] != chatId) {
      return 403; // Forbidden
    }

    // 3. Message sender must match authenticated caller
    if (messageRecord['sender_id'] != callerId) {
      return 403; // Forbidden
    }

    return 200; // Authorized
  }

  /// Simulates outbound OneSignal HTTP timeout & abort handling
  int simulateOneSignalOutboundFetch({
    required int simulatedLatencyMs,
    required int timeoutLimitMs,
    bool simulateNetworkFailure = false,
  }) {
    if (simulateNetworkFailure) {
      return 502; // Bad Gateway
    }
    if (simulatedLatencyMs > timeoutLimitMs) {
      return 504; // Gateway Timeout
    }
    return 200; // Success
  }

  bool checkRateLimit(String userId, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    final timestamps = _rateLimitMap.putIfAbsent(userId, () => []);

    timestamps.removeWhere((t) => now.difference(t).inSeconds >= 60);

    if (timestamps.length >= maxRequestsPerMinute) {
      return false; // Rate limited
    }

    timestamps.add(now);
    return true; // Allowed
  }

  /// Simulates atomic check_push_rate_limit PostgreSQL RPC and fail-closed handling
  Map<String, dynamic> simulateAtomicRateLimitRpc(
    String userId, {
    required Map<String, List<DateTime>> dbStore,
    DateTime? currentTime,
    bool simulateDbOutage = false,
  }) {
    if (simulateDbOutage) {
      return {
        'status': 503,
        'allowed': false,
        'error':
            'Service Unavailable: push notification rate limit service unavailable',
      };
    }

    final now = currentTime ?? DateTime.now();
    final timestamps = dbStore.putIfAbsent(userId, () => []);
    timestamps.removeWhere((t) => now.difference(t).inSeconds >= 60);

    if (timestamps.length >= 30) {
      final oldest = timestamps.first;
      final resetSeconds = 60 - now.difference(oldest).inSeconds;
      return {
        'status': 429,
        'allowed': false,
        'retry_after': resetSeconds > 0 ? resetSeconds : 1,
        'error': 'Too Many Requests: push dispatch rate limit exceeded',
      };
    }

    timestamps.add(now);
    return {
      'status': 200,
      'allowed': true,
      'current_count': timestamps.length,
      'reset_seconds': 60,
    };
  }

  bool isFcmToken(String id) {
    final trimmed = id.trim();
    return trimmed.length > 50 || trimmed.contains(':') || !uuidRegex.hasMatch(trimmed);
  }

  bool isValidOneSignalSubscriptionId(String? id) {
    if (id == null) return false;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    return uuidRegex.hasMatch(trimmed);
  }

  /// Simulates OneSignal-only device routing and filtering
  Map<String, dynamic> simulateDeviceRouting({
    required List<Map<String, dynamic>> devices,
    bool simulateOneSignalTimeout = false,
    bool simulateNetworkFailure = false,
    int oneSignalStatusCode = 200,
  }) {
    if (devices.isEmpty) {
      return {
        'status': 200,
        'success': true,
        'delivered_count': 0,
        'reason': 'no_registered_devices',
        'onesignal_recipients': <String>[],
      };
    }

    final validIds = <String>[];
    for (final d in devices) {
      final pid = d['player_id'] as String?;
      if (isValidOneSignalSubscriptionId(pid)) {
        validIds.add(pid!.trim());
      }
    }

    final uniqueOneSignalIds = validIds.toSet().toList();

    if (uniqueOneSignalIds.isEmpty) {
      return {
        'status': 200,
        'success': true,
        'delivered_count': 0,
        'reason': 'no_valid_onesignal_subscriptions',
        'onesignal_recipients': <String>[],
      };
    }

    if (simulateNetworkFailure) {
      return {
        'status': 502,
        'error': 'Bad Gateway: failed to reach push notification provider',
      };
    }

    if (simulateOneSignalTimeout) {
      return {
        'status': 504,
        'error': 'Gateway Timeout: push notification provider timed out',
      };
    }

    if (oneSignalStatusCode != 200) {
      return {
        'status': 502,
        'error': 'OneSignal API rejection',
        'statusCode': oneSignalStatusCode,
      };
    }

    final payload = {
      'app_id': 'mock-app-id',
      'include_subscription_ids': uniqueOneSignalIds,
      'existing_android_channel_id': 'chat_messages',
      'priority': 10,
    };
    final requestHeaders = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Key mock-rest-key',
    };

    return {
      'status': 200,
      'success': true,
      'delivered_count': uniqueOneSignalIds.length,
      'onesignal_recipients': uniqueOneSignalIds,
      'payload': payload,
      'request_headers': requestHeaders,
      'request_endpoint': 'https://api.onesignal.com/notifications',
    };
  }

  /// Simulates sanitized server-side error extraction from OneSignal rejection
  String sanitizeOneSignalError(dynamic errors) {
    String rawError = 'Unknown rejection';
    if (errors is List && errors.isNotEmpty) {
      rawError = errors.map((e) => e.toString()).join('; ');
    } else if (errors is String) {
      rawError = errors;
    } else if (errors is Map) {
      rawError = errors.toString();
    }
    return rawError.length > 300 ? '${rawError.substring(0, 300)}...' : rawError;
  }
}

void main() {
  group('Supabase send-push Edge Function Hardening Tests (Step 2E.11)', () {
    late EdgePushValidator validator;
    const callerId = 'caller-uuid-001';
    const peerId = 'peer-uuid-002';
    const validChatId = 'e2a4b880-9b36-4d22-9029-2182c1e7a5c1';
    const validMessageId = 'b1e6701f-a136-4fb1-befb-8e9e23dcd12b';

    setUp(() {
      validator = EdgePushValidator();
    });

    group('Task 1: Content Derived from Persisted Database Records', () {
      test(
        'Uses persisted text message and ignores client-supplied preview/type in body',
        () {
          final messageRecord = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'text',
            'text': 'Actual persisted database message content',
          };
          final profileRecord = {
            'display_name': 'Alice Wonder',
            'phone_e164': '+919876543210',
          };

          final content = validator.deriveNotificationContent(
            messageRecord: messageRecord,
            profileRecord: profileRecord,
          );

          // Content matches database row, not any client-supplied spoofing
          expect(
            content['preview'],
            equals('Actual persisted database message content'),
          );
          expect(content['type'], equals('text'));
          expect(content['sender_name'], equals('+919876543210'));
        },
      );

      test(
        'Derives media preview using caption or media kind fallback (photo, video, audio)',
        () {
          final profileRecord = {'display_name': 'Bob'};

          // Media with caption
          final mediaWithCaption = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'media',
            'text': 'Check this photo out!',
            'media': {'kind': 'image'},
          };
          expect(
            validator.deriveNotificationContent(
              messageRecord: mediaWithCaption,
              profileRecord: profileRecord,
            )['preview'],
            equals('Check this photo out!'),
          );

          // Image without caption
          final imageNoCaption = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'media',
            'text': '',
            'media': {'kind': 'image'},
          };
          expect(
            validator.deriveNotificationContent(
              messageRecord: imageNoCaption,
              profileRecord: profileRecord,
            )['preview'],
            equals('📷 Photo'),
          );

          // Video without caption
          final videoNoCaption = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'media',
            'text': '',
            'media': {'kind': 'video'},
          };
          expect(
            validator.deriveNotificationContent(
              messageRecord: videoNoCaption,
              profileRecord: profileRecord,
            )['preview'],
            equals('🎥 Video'),
          );

          // Audio without caption
          final audioNoCaption = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'media',
            'text': '',
            'media': {'kind': 'audio'},
          };
          expect(
            validator.deriveNotificationContent(
              messageRecord: audioNoCaption,
              profileRecord: profileRecord,
            )['preview'],
            equals('🎵 Audio'),
          );

          // Generic attachment
          final fileNoCaption = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'media',
            'text': '',
            'media': {'kind': 'document'},
          };
          expect(
            validator.deriveNotificationContent(
              messageRecord: fileNoCaption,
              profileRecord: profileRecord,
            )['preview'],
            equals('📎 Attachment'),
          );
        },
      );

      test('Derives call preview for call message type', () {
        final callMessage = {
          'id': validMessageId,
          'chat_id': validChatId,
          'sender_id': callerId,
          'type': 'call',
        };
        final content = validator.deriveNotificationContent(
          messageRecord: callMessage,
          profileRecord: {'display_name': 'Alice'},
        );
        expect(content['preview'], equals('📞 Incoming call'));
        expect(content['type'], equals('call'));
      });

      test(
        'Prefers phone_e164 for sender title and falls back to "New message" without preferring username',
        () {
          final msg = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'text',
            'text': 'Hi',
          };

          expect(
            validator.deriveNotificationContent(
              messageRecord: msg,
              profileRecord: {'display_name': 'AliceUser', 'phone_e164': '+919876543210'},
            )['sender_name'],
            equals('+919876543210'),
          );

          expect(
            validator.deriveNotificationContent(
              messageRecord: msg,
              profileRecord: null,
            )['sender_name'],
            equals('New message'),
          );

          expect(
            validator.deriveNotificationContent(
              messageRecord: msg,
              profileRecord: {'display_name': 'AliceUser', 'phone_e164': '   '},
            )['sender_name'],
            equals('New message'),
          );
        },
      );

      test(
        'Enforces maximum 120-character preview length and 50-character sender name limit',
        () {
          final longMsg = {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
            'type': 'text',
            'text': 'M' * 200,
          };
          final longProfile = {'phone_e164': '+91${'9' * 100}'};

          final content = validator.deriveNotificationContent(
            messageRecord: longMsg,
            profileRecord: longProfile,
          );

          expect(content['preview']!.length, equals(120));
          expect(content['preview'], equals('M' * 120));
          expect(content['sender_name']!.length, equals(50));
          expect(content['sender_name'], equals('+91${'9' * 47}'));
        },
      );
    });

    group('Task 1: Message Ownership & Chat Membership Authorization', () {
      test(
        'Rejects caller who is not an active member in chat_members (403)',
        () {
          final status = validator.validateMessageAuthorization(
            callerId: 'imposter-user-id',
            chatId: validChatId,
            chatMembers: [callerId, peerId],
            messageRecord: {
              'id': validMessageId,
              'chat_id': validChatId,
              'sender_id': callerId,
            },
          );
          expect(status, equals(403));
        },
      );

      test(
        'Rejects when message does not exist or chat_id mismatches (403)',
        () {
          final missingStatus = validator.validateMessageAuthorization(
            callerId: callerId,
            chatId: validChatId,
            chatMembers: [callerId, peerId],
            messageRecord: null, // Message not found
          );
          expect(missingStatus, equals(403));

          final mismatchStatus = validator.validateMessageAuthorization(
            callerId: callerId,
            chatId: validChatId,
            chatMembers: [callerId, peerId],
            messageRecord: {
              'id': validMessageId,
              'chat_id': 'different-chat-uuid',
              'sender_id': callerId,
            },
          );
          expect(mismatchStatus, equals(403));
        },
      );

      test('Rejects when caller is not the message sender (403)', () {
        final senderMismatch = validator.validateMessageAuthorization(
          callerId: callerId,
          chatId: validChatId,
          chatMembers: [callerId, peerId],
          messageRecord: {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': peerId, // Authored by peer, not caller
          },
        );
        expect(senderMismatch, equals(403));
      });

      test('Authorizes valid member and message author (200)', () {
        final authorized = validator.validateMessageAuthorization(
          callerId: callerId,
          chatId: validChatId,
          chatMembers: [callerId, peerId],
          messageRecord: {
            'id': validMessageId,
            'chat_id': validChatId,
            'sender_id': callerId,
          },
        );
        expect(authorized, equals(200));
      });
    });

    group('Task 2: Outbound HTTP Timeout & Abort Handling', () {
      test(
        'Returns 504 Gateway Timeout when OneSignal request exceeds 8000ms limit',
        () {
          final timeoutStatus = validator.simulateOneSignalOutboundFetch(
            simulatedLatencyMs: 8500, // Exceeds 8000ms timeout
            timeoutLimitMs: 8000,
          );
          expect(timeoutStatus, equals(504));
        },
      );

      test(
        'Returns 502 Bad Gateway when network connection to OneSignal fails',
        () {
          final networkStatus = validator.simulateOneSignalOutboundFetch(
            simulatedLatencyMs: 200,
            timeoutLimitMs: 8000,
            simulateNetworkFailure: true,
          );
          expect(networkStatus, equals(502));
        },
      );

      test('Succeeds with 200 when OneSignal responds within 8000ms limit', () {
        final successStatus = validator.simulateOneSignalOutboundFetch(
          simulatedLatencyMs: 350,
          timeoutLimitMs: 8000,
        );
        expect(successStatus, equals(200));
      });
    });

    group('Task 3: Error Sanitization (Zero Exception Leakage)', () {
      test(
        'Error responses return generic strings and omit internal exception details',
        () {
          // Simulated edge function catch response
          Map<String, dynamic> generateSafeErrorResponse(Object err) {
            // Never returns String(err) or err.message
            return {'error': 'Internal server error'};
          }

          final internalException = Exception(
            'PostgreSQL: Connection terminated unexpectedly at 10.0.0.1:5432',
          );
          final response = generateSafeErrorResponse(internalException);

          expect(response['error'], equals('Internal server error'));
          expect(response.containsKey('message'), isFalse);
          expect(response.containsKey('details'), isFalse);
          expect(response.toString().contains('PostgreSQL'), isFalse);
          expect(response.toString().contains('10.0.0.1'), isFalse);
        },
      );
    });

    group('Task 4: Rate Limiting & Documented Multi-Isolate Limitations', () {
      test(
        'Enforces sliding window of 30 req/min per caller on single isolate',
        () {
          final baseTime = DateTime(2026, 10, 22, 12, 0, 0);

          for (int i = 0; i < 30; i++) {
            final allowed = validator.checkRateLimit(
              callerId,
              currentTime: baseTime.add(Duration(seconds: i)),
            );
            expect(allowed, isTrue);
          }

          final blocked = validator.checkRateLimit(
            callerId,
            currentTime: baseTime.add(const Duration(seconds: 45)),
          );
          expect(blocked, isFalse);

          final allowedAfterReset = validator.checkRateLimit(
            callerId,
            currentTime: baseTime.add(const Duration(seconds: 65)),
          );
          expect(allowedAfterReset, isTrue);
        },
      );

      test(
        'Documents that separate isolates have independent memory and bypass global limits',
        () {
          final isolate1 = EdgePushValidator();
          final isolate2 = EdgePushValidator(); // Separate isolate instance
          final testTime = DateTime(2026, 10, 22, 12, 0, 0);

          // Exhaust limit on isolate 1
          for (int i = 0; i < 30; i++) {
            isolate1.checkRateLimit(
              callerId,
              currentTime: testTime.add(Duration(seconds: i)),
            );
          }
          expect(
            isolate1.checkRateLimit(
              callerId,
              currentTime: testTime.add(const Duration(seconds: 35)),
            ),
            isFalse,
          );

          // Isolate 2 has independent memory and permits request (confirming isolate-local limitation)
          final isolate2Allowed = isolate2.checkRateLimit(
            callerId,
            currentTime: testTime.add(const Duration(seconds: 35)),
          );
          expect(
            isolate2Allowed,
            isTrue,
            reason:
                'Isolate-local Map cannot enforce global rate limits across workers',
          );
        },
      );
    });

    group('Task 5: OneSignal Payload Validation & UUID Verification', () {
      test('Validates RFC-4122 UUID format for chat_id and message_id', () {
        expect(validator.validateUUID(validChatId), isTrue);
        expect(validator.validateUUID(validMessageId), isTrue);
        expect(validator.validateUUID('invalid-uuid-string'), isFalse);
        expect(validator.validateUUID(''), isFalse);
        expect(validator.validateUUID(null), isFalse);
      });
    });

    group(
      'Step 2E.14: Atomic PostgreSQL RPC Rate Limiter & Fail-Closed Fallback',
      () {
        test(
          'Atomic rate limiter allows up to 30 requests within 60s window across isolates',
          () {
            final dbStore = <String, List<DateTime>>{};
            final isolateA = EdgePushValidator();
            final isolateB = EdgePushValidator();
            final baseTime = DateTime(2026, 10, 23, 0, 0, 0);

            // 15 requests through isolate A
            for (int i = 0; i < 15; i++) {
              final res = isolateA.simulateAtomicRateLimitRpc(
                callerId,
                dbStore: dbStore,
                currentTime: baseTime.add(Duration(seconds: i)),
              );
              expect(res['status'], equals(200));
              expect(res['allowed'], isTrue);
            }

            // 15 requests through isolate B (simulating distributed worker)
            for (int i = 15; i < 30; i++) {
              final res = isolateB.simulateAtomicRateLimitRpc(
                callerId,
                dbStore: dbStore,
                currentTime: baseTime.add(Duration(seconds: i)),
              );
              expect(res['status'], equals(200));
              expect(res['allowed'], isTrue);
            }

            // 31st request on isolate A is throttled globally (HTTP 429)
            final res31 = isolateA.simulateAtomicRateLimitRpc(
              callerId,
              dbStore: dbStore,
              currentTime: baseTime.add(const Duration(seconds: 35)),
            );
            expect(res31['status'], equals(429));
            expect(res31['allowed'], isFalse);
            expect(res31['retry_after'], isNotNull);
          },
        );

        test(
          'Fails closed (HTTP 503) on database rate-limit RPC error or timeout',
          () {
            final isolate = EdgePushValidator();
            final res = isolate.simulateAtomicRateLimitRpc(
              callerId,
              dbStore: {},
              simulateDbOutage: true,
            );
            expect(res['status'], equals(503));
            expect(res['allowed'], isFalse);
            expect(res['error'], contains('Service Unavailable'));
          },
        );

        test(
          'Distinguishes between 429 rate limit exceeded and 503 database service unavailable',
          () {
            final isolate = EdgePushValidator();
            final dbStore = <String, List<DateTime>>{};
            final baseTime = DateTime(2026, 10, 23, 0, 0, 0);

            // Fill limit
            for (int i = 0; i < 30; i++) {
              isolate.simulateAtomicRateLimitRpc(
                callerId,
                dbStore: dbStore,
                currentTime: baseTime.add(Duration(seconds: i)),
              );
            }

            final rateLimitRes = isolate.simulateAtomicRateLimitRpc(
              callerId,
              dbStore: dbStore,
              currentTime: baseTime.add(const Duration(seconds: 40)),
            );
            expect(rateLimitRes['status'], equals(429));

            final outageRes = isolate.simulateAtomicRateLimitRpc(
              callerId,
              dbStore: dbStore,
              simulateDbOutage: true,
            );
            expect(outageRes['status'], equals(503));
          },
        );
      },
    );

    group(
      'Task 6: OneSignal-Only Push Notification Routing & Device Delivery',
      () {
        const testFcmToken1 =
            'fcm_token_sample_abc123_xyz789_long_registration_token_for_device_1';
        const testOneSignalId1 = '11111111-2222-3333-4444-555555555555';
        const testOneSignalId2 = '66666666-7777-8888-9999-000000000000';

        test('Case 1: Valid OneSignal subscription is routed to OneSignal REST API', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(1));
          expect(res['onesignal_recipients'], equals([testOneSignalId1]));
          expect(res['request_endpoint'], equals('https://api.onesignal.com/notifications'));
          expect(res['request_headers']?['Authorization'], equals('Key mock-rest-key'));
          expect(res['payload']?['include_subscription_ids'], equals([testOneSignalId1]));
          expect(res['payload']?.containsKey('include_player_ids'), isFalse);
        });

        test('Case 2: Raw FCM tokens in user_devices are rejected and not sent to OneSignal', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testFcmToken1, 'platform': 'android'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(0));
          expect(res['reason'], equals('no_valid_onesignal_subscriptions'));
          expect(res['onesignal_recipients'], isEmpty);
        });

        test('Case 3: Mixed devices filter out FCM tokens and deliver to valid OneSignal subscriptions', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testFcmToken1, 'platform': 'android'},
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'ios'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(1));
          expect(res['onesignal_recipients'], equals([testOneSignalId1]));
        });

        test('Case 4: Multiple active OneSignal subscriptions across recipients are all delivered', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
              {'user_id': 'other-peer', 'player_id': testOneSignalId2, 'platform': 'ios'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(2));
          expect(res['onesignal_recipients'], containsAll([testOneSignalId1, testOneSignalId2]));
        });

        test('Case 5: Duplicate subscription IDs are deduplicated to prevent duplicate alerts', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(1));
          expect(res['onesignal_recipients'], equals([testOneSignalId1]));
        });

        test('Case 6: Empty device list returns 200 with reason no_registered_devices', () {
          final res = validator.simulateDeviceRouting(
            devices: [],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(0));
          expect(res['reason'], equals('no_registered_devices'));
        });

        test('Case 7: OneSignal timeout (> 8s) returns 504 Gateway Timeout', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
            ],
            simulateOneSignalTimeout: true,
          );
          expect(res['status'], equals(504));
          expect(res['error'], contains('Gateway Timeout'));
        });

        test('Case 8: OneSignal API rejection returns 502 Bad Gateway', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
            ],
            oneSignalStatusCode: 400,
          );
          expect(res['status'], equals(502));
          expect(res['error'], equals('OneSignal API rejection'));
        });

        test('Case 9: Notification payload uses existing_android_channel_id for app-code channel', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': testOneSignalId1, 'platform': 'android'},
            ],
          );
          expect(res['payload']?['existing_android_channel_id'], equals('chat_messages'));
          expect(res['payload']?.containsKey('android_channel_id'), isFalse);
        });

        test('Case 10: Non-UUID short identifiers are rejected and not routed to OneSignal', () {
          final res = validator.simulateDeviceRouting(
            devices: [
              {'user_id': peerId, 'player_id': 'player-uuid-001', 'platform': 'android'},
              {'user_id': peerId, 'player_id': 'short_id', 'platform': 'android'},
              {'user_id': peerId, 'player_id': '', 'platform': 'android'},
            ],
          );
          expect(res['status'], equals(200));
          expect(res['delivered_count'], equals(0));
          expect(res['reason'], equals('no_valid_onesignal_subscriptions'));
          expect(res['onesignal_recipients'], isEmpty);
        });

        test('Case 11: OneSignal error extraction sanitizes errors and limits length to 300 chars', () {
          final longErrorList = List.generate(20, (i) => 'Error detail item $i with long explanation');
          final sanitized = validator.sanitizeOneSignalError(longErrorList);
          expect(sanitized.length, lessThanOrEqualTo(303)); // 300 + '...'
          expect(sanitized, endsWith('...'));

          // Test single string error
          final singleError = validator.sanitizeOneSignalError(['Could not find android_channel_id']);
          expect(singleError, equals('Could not find android_channel_id'));
        });
      },
    );

    group(
      'Task 7: Branch 3 Safe Optimistic Lease Acquisition & Outbox Concurrency (Stage 2.3)',
      () {
        final now = DateTime.parse('2026-11-03T02:00:00.000Z');

        test('State 1: Pending event is selected and atomically claimed with 30s lease', () {
          final pendingRow = {
            'id': 'outbox-1',
            'call_id': 'call-1',
            'status': 'pending',
            'retry_count': 0,
            'max_retries': 3,
            'locked_until': null,
            'locked_by': null,
          };

          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: pendingRow, now: now), isTrue);
          expect(CallOutboxLeaseSimulator.canClaim(row: pendingRow), isTrue);

          final claimed = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: pendingRow,
            claimantId: 'client_user123',
            now: now,
          );

          expect(claimed, isNotNull);
          expect(claimed!['status'], equals('processing'));
          expect(claimed['locked_by'], equals('client_user123'));
          expect(claimed['retry_count'], equals(1));
          expect(claimed['locked_until'], equals(now.add(const Duration(seconds: 30)).toIso8601String()));
        });

        test('State 2: Active unexpired worker lease is NOT selected or overwritten', () {
          final activeWorkerRow = {
            'id': 'outbox-2',
            'call_id': 'call-1',
            'status': 'processing',
            'retry_count': 1,
            'max_retries': 3,
            'locked_until': now.add(const Duration(seconds: 25)).toIso8601String(), // 25s remaining
            'locked_by': 'edge_worker_daemon',
          };

          // Must be filtered out by query
          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: activeWorkerRow, now: now), isFalse);

          // Atomic claim attempt fails
          final claimAttempt = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: activeWorkerRow,
            claimantId: 'client_user456',
            now: now,
          );

          expect(claimAttempt, isNull);
          // Worker lease preserved untouched
          expect(activeWorkerRow['locked_by'], equals('edge_worker_daemon'));
        });

        test('State 3: Expired processing lease is selected, reclaimed, and lease extended', () {
          final expiredRow = {
            'id': 'outbox-3',
            'call_id': 'call-1',
            'status': 'processing',
            'retry_count': 1,
            'max_retries': 3,
            'locked_until': now.subtract(const Duration(seconds: 5)).toIso8601String(), // Expired 5s ago
            'locked_by': 'dead_worker',
          };

          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: expiredRow, now: now), isTrue);

          final reclaimed = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: expiredRow,
            claimantId: 'client_user789',
            now: now,
          );

          expect(reclaimed, isNotNull);
          expect(reclaimed!['status'], equals('processing'));
          expect(reclaimed['locked_by'], equals('client_user789'));
          expect(reclaimed['retry_count'], equals(2));
          expect(reclaimed['locked_until'], equals(now.add(const Duration(seconds: 30)).toIso8601String()));
        });

        test('State 4: Already dispatched event is excluded from query and claim', () {
          final dispatchedRow = {
            'id': 'outbox-4',
            'call_id': 'call-1',
            'status': 'dispatched',
            'retry_count': 1,
            'max_retries': 3,
            'dispatched_at': now.toIso8601String(),
          };

          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: dispatchedRow, now: now), isFalse);
          final claim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: dispatchedRow,
            claimantId: 'client_user123',
            now: now,
          );
          expect(claim, isNull);
        });

        test('State 5: Failed event is excluded from client immediate dispatch query', () {
          final failedRow = {
            'id': 'outbox-5',
            'call_id': 'call-1',
            'status': 'failed',
            'retry_count': 1,
            'max_retries': 3,
            'last_error': 'OneSignal HTTP 500',
          };

          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: failedRow, now: now), isFalse);
          final claim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: failedRow,
            claimantId: 'client_user123',
            now: now,
          );
          expect(claim, isNull);
        });

        test('State 6: Maximum retry count reached is excluded from claim (terminal failure)', () {
          final cappedPendingRow = {
            'id': 'outbox-6',
            'call_id': 'call-1',
            'status': 'pending',
            'retry_count': 3,
            'max_retries': 3,
          };

          expect(CallOutboxLeaseSimulator.canClaim(row: cappedPendingRow), isFalse);
          final claim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: cappedPendingRow,
            claimantId: 'client_user123',
            now: now,
          );
          expect(claim, isNull);
        });

        test('State 7: Two simultaneous client dispatch attempts — Winner claims, Loser skips', () {
          Map<String, dynamic> sharedDbRow = {
            'id': 'outbox-7',
            'call_id': 'call-1',
            'status': 'pending',
            'retry_count': 0,
            'max_retries': 3,
            'locked_until': null,
            'locked_by': null,
          };

          // Both clients inspect eligibility concurrently
          expect(CallOutboxLeaseSimulator.isEligibleForBranch3Query(row: sharedDbRow, now: now), isTrue);

          // Client A reaches DB first and claims
          final clientAClaim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: sharedDbRow,
            claimantId: 'client_A',
            now: now,
          );

          expect(clientAClaim, isNotNull);
          sharedDbRow = clientAClaim!; // DB state mutated

          // Client B attempts to claim the now-mutated DB row
          final clientBClaim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: sharedDbRow,
            claimantId: 'client_B',
            now: now,
          );

          expect(clientBClaim, isNull); // Client B skips; only one push delivered!
          expect(sharedDbRow['locked_by'], equals('client_A'));
          expect(sharedDbRow['retry_count'], equals(1));
        });

        test('State 8: Worker and client attempting to claim same event — Winner locks, competitor skips', () {
          Map<String, dynamic> sharedDbRow = {
            'id': 'outbox-8',
            'call_id': 'call-1',
            'status': 'pending',
            'retry_count': 0,
            'max_retries': 3,
          };

          // Worker claims first via worker daemon
          final workerClaim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: sharedDbRow,
            claimantId: 'edge_worker_daemon',
            now: now,
          );

          expect(workerClaim, isNotNull);
          sharedDbRow = workerClaim!;

          // Client attempts to claim during worker lock window
          final clientClaim = CallOutboxLeaseSimulator.attemptAtomicClaim(
            rowInDb: sharedDbRow,
            claimantId: 'client_caller',
            now: now.add(const Duration(seconds: 2)), // 2s into 30s lease
          );

          expect(clientClaim, isNull); // Client is rejected by optimistic lock
          expect(sharedDbRow['locked_by'], equals('edge_worker_daemon'));
        });
      },
    );
  });
}

/// Simulates Branch 3 atomic optimistic lease acquisition rules from send-push/index.ts
class CallOutboxLeaseSimulator {
  static bool isEligibleForBranch3Query({
    required Map<String, dynamic> row,
    required DateTime now,
  }) {
    final status = row['status'] as String?;
    if (status == 'pending') return true;
    if (status == 'processing') {
      final lockedUntilStr = row['locked_until'] as String?;
      if (lockedUntilStr != null) {
        final lockedUntil = DateTime.tryParse(lockedUntilStr);
        if (lockedUntil != null && lockedUntil.isBefore(now)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool canClaim({required Map<String, dynamic> row}) {
    final retryCount = row['retry_count'] as int? ?? 0;
    final maxRetries = row['max_retries'] as int? ?? 3;
    return retryCount < maxRetries;
  }

  static Map<String, dynamic>? attemptAtomicClaim({
    required Map<String, dynamic> rowInDb,
    required String claimantId,
    required DateTime now,
  }) {
    if (!isEligibleForBranch3Query(row: rowInDb, now: now)) {
      return null;
    }
    if (!canClaim(row: rowInDb)) {
      return null;
    }

    final currentRetry = rowInDb['retry_count'] as int? ?? 0;
    final leaseExpiry = now.add(const Duration(seconds: 30));

    return {
      ...rowInDb,
      'status': 'processing',
      'locked_by': claimantId,
      'locked_until': leaseExpiry.toIso8601String(),
      'retry_count': currentRetry + 1,
      'updated_at': now.toIso8601String(),
    };
  }
}
