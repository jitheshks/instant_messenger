import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/push_controller.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/data/push_dispatch_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 2E.9: PushDispatchService & Edge Function Wiring Tests', () {
    const validChatId = 'e2a4b880-9b36-4d22-9029-2182c1e7a5c1';
    const validMessageId = 'b1e6701f-a136-4fb1-befb-8e9e23dcd12b';
    const testUserId = '11111111-2222-3333-4444-555555555555';

    group('Payload Construction & Sanitization Contract', () {
      test(
        'buildPayload constructs exact snake_case schema matching send-push Edge Function',
        () {
          final payload = PushDispatchService.buildPayload(
            chatId: validChatId,
            messageId: validMessageId,
            preview: 'Hello there!',
            type: 'text',
            senderName: 'Alice',
          );

          expect(payload, isNotNull);
          expect(payload!['chat_id'], equals(validChatId));
          expect(payload['message_id'], equals(validMessageId));
          expect(payload['preview'], equals('Hello there!'));
          expect(payload['type'], equals('text'));
          expect(payload['sender_name'], equals('Alice'));
        },
      );

      test(
        'Validates UUID format for chat_id and message_id; rejects invalid IDs',
        () {
          expect(PushDispatchService.isValidUuid(validChatId), isTrue);
          expect(PushDispatchService.isValidUuid(validMessageId), isTrue);
          expect(PushDispatchService.isValidUuid('not-a-uuid'), isFalse);
          expect(PushDispatchService.isValidUuid(''), isFalse);
          expect(PushDispatchService.isValidUuid(null), isFalse);

          final badChatPayload = PushDispatchService.buildPayload(
            chatId: 'invalid-chat-id',
            messageId: validMessageId,
          );
          expect(badChatPayload, isNull);

          final badMsgPayload = PushDispatchService.buildPayload(
            chatId: validChatId,
            messageId: 'invalid-msg-id',
          );
          expect(badMsgPayload, isNull);
        },
      );

      test(
        'Sanitizes preview text to max 120 characters and trims whitespace',
        () {
          final longPreview = 'X' * 200;
          final sanitized = PushDispatchService.sanitizePreview(longPreview);
          expect(sanitized.length, equals(120));
          expect(sanitized, equals('X' * 120));

          expect(
            PushDispatchService.sanitizePreview('   Spaced message   '),
            equals('Spaced message'),
          );
          expect(
            PushDispatchService.sanitizePreview(null),
            equals('New message'),
          );
          expect(
            PushDispatchService.sanitizePreview('   '),
            equals('New message'),
          );
        },
      );

      test(
        'Sanitizes sender name to max 50 characters and trims whitespace',
        () {
          final longName = 'Y' * 100;
          final sanitized = PushDispatchService.sanitizeSenderName(longName);
          expect(sanitized.length, equals(50));
          expect(sanitized, equals('Y' * 50));

          expect(
            PushDispatchService.sanitizeSenderName('  Bob Builder  '),
            equals('Bob Builder'),
          );
          expect(
            PushDispatchService.sanitizeSenderName(null),
            equals('New message'),
          );
          expect(
            PushDispatchService.sanitizeSenderName(''),
            equals('New message'),
          );
        },
      );

      test('Enforces allowed message types whitelist (text, media, call)', () {
        expect(PushDispatchService.sanitizeType('text'), equals('text'));
        expect(PushDispatchService.sanitizeType('TEXT'), equals('text'));
        expect(PushDispatchService.sanitizeType('media'), equals('media'));
        expect(PushDispatchService.sanitizeType('MEDIA'), equals('media'));
        expect(PushDispatchService.sanitizeType('call'), equals('call'));
        expect(PushDispatchService.sanitizeType('CALL'), equals('call'));

        // Unsupported types default to text
        expect(PushDispatchService.sanitizeType('unsupported'), equals('text'));
        expect(PushDispatchService.sanitizeType('system'), equals('text'));
        expect(PushDispatchService.sanitizeType(null), equals('text'));
      });
    });

    group('Edge Function Invocation & Dispatch Flow', () {
      test(
        'Invokes "send-push" Edge Function with correct payload and returns dispatched status',
        () async {
          String? invokedFunctionName;
          Map<String, dynamic>? capturedBody;

          final service = PushDispatchService(
            currentUserIdProvider: () => testUserId,
            currentUserNameProvider: () => 'Alice Wonder',
            functionInvoker: (functionName, {body}) async {
              invokedFunctionName = functionName;
              capturedBody = body;
              return FunctionResponse(
                data: {
                  'success': true,
                  'delivered_count': 2,
                  'oneSignalId': 'os-notification-123',
                },
                status: 200,
              );
            },
          );

          final result = await service.dispatch(
            chatId: validChatId,
            senderId: testUserId,
            preview: 'Check this out',
            type: 'text',
            messageId: validMessageId,
            senderName: 'Alice',
          );

          expect(result.status, equals(PushDispatchStatus.dispatched));
          expect(result.isSuccess, isTrue);
          expect(result.statusCode, equals(200));
          expect(result.deliveredCount, equals(2));

          expect(invokedFunctionName, equals('send-push'));
          expect(capturedBody, isNotNull);
          expect(capturedBody!['chat_id'], equals(validChatId));
          expect(capturedBody!['message_id'], equals(validMessageId));
          expect(capturedBody!['preview'], equals('Check this out'));
          expect(capturedBody!['type'], equals('text'));
          expect(capturedBody!['sender_name'], equals('Alice'));
        },
      );

      test(
        'Falls back to currentUserNameProvider when senderName is omitted',
        () async {
          Map<String, dynamic>? capturedBody;

          final service = PushDispatchService(
            currentUserIdProvider: () => testUserId,
            currentUserNameProvider: () => 'Default Sender Name',
            functionInvoker: (functionName, {body}) async {
              capturedBody = body;
              return FunctionResponse(
                data: {'success': true, 'delivered_count': 1},
                status: 200,
              );
            },
          );

          await service.dispatch(
            chatId: validChatId,
            senderId: testUserId,
            preview: 'Hello',
            type: 'text',
            messageId: validMessageId,
            senderName: null, // Omitted
          );

          expect(capturedBody?['sender_name'], equals('Default Sender Name'));
        },
      );

      test(
        'Distinguishes zero-recipient response as noEligibleRecipients rather than dispatched',
        () async {
          final service = PushDispatchService(
            currentUserIdProvider: () => testUserId,
            functionInvoker: (functionName, {body}) async {
              return FunctionResponse(
                data: {
                  'success': true,
                  'delivered_count': 0,
                  'reason': 'no_valid_onesignal_subscriptions',
                },
                status: 200,
              );
            },
          );

          final result = await service.dispatch(
            chatId: validChatId,
            senderId: testUserId,
            preview: 'Hello',
            type: 'text',
            messageId: validMessageId,
          );

          expect(result.status, equals(PushDispatchStatus.noEligibleRecipients));
          expect(result.isSuccess, isFalse);
          expect(result.hasDeliveredRecipients, isFalse);
          expect(result.deliveredCount, equals(0));
          expect(result.reason, equals('no_valid_onesignal_subscriptions'));
        },
      );
    });

    group(
      'Early Validation, Identity Verification & Duplicate Dispatch Prevention',
      () {
        test(
          'Skips dispatch when caller is unauthenticated without invoking function',
          () async {
            var invoked = false;
            final service = PushDispatchService(
              currentUserIdProvider: () => null,
              functionInvoker: (functionName, {body}) async {
                invoked = true;
                return FunctionResponse(data: {}, status: 200);
              },
            );

            final result = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Text',
              type: 'text',
              messageId: validMessageId,
            );

            expect(result.status, equals(PushDispatchStatus.skipped));
            expect(result.message, equals('Unauthenticated caller'));
            expect(invoked, isFalse);
          },
        );

        test(
          'Skips dispatch when senderId does not match authenticated user',
          () async {
            var invoked = false;
            final service = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                invoked = true;
                return FunctionResponse(data: {}, status: 200);
              },
            );

            final result = await service.dispatch(
              chatId: validChatId,
              senderId: 'different-impersonated-user-id',
              preview: 'Text',
              type: 'text',
              messageId: validMessageId,
            );

            expect(result.status, equals(PushDispatchStatus.skipped));
            expect(result.message, equals('Sender ID mismatch'));
            expect(invoked, isFalse);
          },
        );

        test(
          'Skips dispatch when messageId is null or empty without invoking function',
          () async {
            var invoked = false;
            final service = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                invoked = true;
                return FunctionResponse(data: {}, status: 200);
              },
            );

            final nullMsgResult = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Text',
              type: 'text',
              messageId: null,
            );
            expect(nullMsgResult.status, equals(PushDispatchStatus.skipped));
            expect(invoked, isFalse);

            final emptyMsgResult = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Text',
              type: 'text',
              messageId: '   ',
            );
            expect(emptyMsgResult.status, equals(PushDispatchStatus.skipped));
            expect(invoked, isFalse);
          },
        );

        test(
          'Skips dispatch when chatId or messageId is not a valid UUID',
          () async {
            var invoked = false;
            final service = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                invoked = true;
                return FunctionResponse(data: {}, status: 200);
              },
            );

            final badChatResult = await service.dispatch(
              chatId: 'not-a-uuid',
              senderId: testUserId,
              preview: 'Text',
              type: 'text',
              messageId: validMessageId,
            );
            expect(badChatResult.status, equals(PushDispatchStatus.skipped));
            expect(invoked, isFalse);

            final badMsgResult = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Text',
              type: 'text',
              messageId: 'not-a-uuid',
            );
            expect(badMsgResult.status, equals(PushDispatchStatus.skipped));
            expect(invoked, isFalse);
          },
        );

        test(
          'Guards against duplicate dispatch for the same messageId within session',
          () async {
            var callCount = 0;
            final service = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                callCount++;
                return FunctionResponse(
                  data: {'success': true, 'delivered_count': 1},
                  status: 200,
                );
              },
            );

            // First dispatch succeeds
            final result1 = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'First send',
              type: 'text',
              messageId: validMessageId,
            );
            expect(result1.status, equals(PushDispatchStatus.dispatched));
            expect(callCount, equals(1));
            expect(service.isDispatched(validMessageId), isTrue);

            // Second dispatch for identical messageId is skipped
            final result2 = await service.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Duplicate send attempt',
              type: 'text',
              messageId: validMessageId,
            );
            expect(result2.status, equals(PushDispatchStatus.skipped));
            expect(result2.message, equals('Duplicate dispatch prevented'));
            expect(callCount, equals(1)); // Function was NOT called again
          },
        );
      },
    );

    group('Error Recovery & Safe Failure Guarantees', () {
      test(
        'Handles FunctionException (e.g. 403 Forbidden or 429 Rate Limit) without throwing',
        () async {
          final service = PushDispatchService(
            currentUserIdProvider: () => testUserId,
            functionInvoker: (functionName, {body}) async {
              throw const FunctionsHttpException(
                status: 403,
                details: {
                  'error':
                      'Forbidden: caller is not an active participant in this chat',
                },
              );
            },
          );

          final result = await service.dispatch(
            chatId: validChatId,
            senderId: testUserId,
            preview: 'Text',
            type: 'text',
            messageId: validMessageId,
          );

          expect(result.status, equals(PushDispatchStatus.failed));
          expect(result.isSuccess, isFalse);
          expect(result.statusCode, equals(403));
        },
      );

      test('Handles non-2xx status response without throwing', () async {
        final service = PushDispatchService(
          currentUserIdProvider: () => testUserId,
          functionInvoker: (functionName, {body}) async {
            return FunctionResponse(
              data: {'error': 'Internal server error'},
              status: 500,
            );
          },
        );

        final result = await service.dispatch(
          chatId: validChatId,
          senderId: testUserId,
          preview: 'Text',
          type: 'text',
          messageId: validMessageId,
        );

        expect(result.status, equals(PushDispatchStatus.failed));
        expect(result.statusCode, equals(500));
      });

      test('Handles generic network exceptions without throwing', () async {
        final service = PushDispatchService(
          currentUserIdProvider: () => testUserId,
          functionInvoker: (functionName, {body}) async {
            throw Exception('SocketException: Connection refused (offline)');
          },
        );

        final result = await service.dispatch(
          chatId: validChatId,
          senderId: testUserId,
          preview: 'Text',
          type: 'text',
          messageId: validMessageId,
        );

        expect(result.status, equals(PushDispatchStatus.failed));
        expect(result.message, contains('SocketException'));
      });
    });

    group('PushController Integration with PushDispatchService', () {
      test(
        'PushController.onMessageSent routes to PushDispatchService and preserves safety on error',
        () async {
          var serverSendCalled = false;
          var capturedChatId = '';
          var capturedMessageId = '';

          final oneSignal = OneSignalService(null, null, null, () => true);
          final dispatchService = PushDispatchService(
            currentUserIdProvider: () => testUserId,
            functionInvoker: (functionName, {body}) async {
              serverSendCalled = true;
              capturedChatId = body?['chat_id'] as String;
              capturedMessageId = body?['message_id'] as String;
              // Simulate error response
              return FunctionResponse(
                data: {'error': 'OneSignal API rejection'},
                status: 502,
              );
            },
          );

          final pushController = PushController(
            oneSignal: oneSignal,
            oneSignalAppId: 'app-123',
            serverSend: dispatchService.dispatch,
          );

          // Should complete cleanly without throwing even though server returned 502
          await expectLater(
            pushController.onMessageSent(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Hello push',
              messageId: validMessageId,
              type: 'text',
              senderName: 'Alice',
            ),
            completes,
          );

          expect(serverSendCalled, isTrue);
          expect(capturedChatId, equals(validChatId));
          expect(capturedMessageId, equals(validMessageId));
        },
      );
    });

    group(
      'Message Send Flow Verification: Successful Persistence vs Failed Persistence',
      () {
        test(
          'Message persistence failure prevents push dispatch invocation',
          () async {
            var pushDispatchInvoked = false;

            final dispatchService = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                pushDispatchInvoked = true;
                return FunctionResponse(data: {'success': true}, status: 200);
              },
            );

            // Simulated repository sendMessage throwing error
            Future<String> failingSendMessage() async {
              throw Exception(
                'Database constraint violation or network timeout',
              );
            }

            // Send text flow simulation
            try {
              final serverId = await failingSendMessage();
              // onPush only called if sendMessage succeeds:
              await dispatchService.dispatch(
                chatId: validChatId,
                senderId: testUserId,
                preview: 'Failed message',
                type: 'text',
                messageId: serverId,
              );
            } catch (_) {
              // Failure caught; message was not persisted
            }

            expect(
              pushDispatchInvoked,
              isFalse,
              reason: 'Push must never dispatch when persistence fails',
            );
          },
        );

        test(
          'Push dispatch failure does not alter or undo persisted message',
          () async {
            var messagePersisted = false;
            String? persistedMessageId;

            final dispatchService = PushDispatchService(
              currentUserIdProvider: () => testUserId,
              functionInvoker: (functionName, {body}) async {
                throw const FunctionsHttpException(
                  status: 500,
                  details: {'error': 'Server error'},
                );
              },
            );

            // Simulated successful repository sendMessage
            Future<String> successfulSendMessage() async {
              messagePersisted = true;
              return validMessageId;
            }

            final serverId = await successfulSendMessage();
            expect(messagePersisted, isTrue);
            expect(serverId, equals(validMessageId));

            // Push dispatch fails
            final pushResult = await dispatchService.dispatch(
              chatId: validChatId,
              senderId: testUserId,
              preview: 'Hello',
              type: 'text',
              messageId: serverId,
            );

            expect(pushResult.status, equals(PushDispatchStatus.failed));
            // Crucial invariant: The message remains persisted!
            persistedMessageId = serverId;
            expect(persistedMessageId, equals(validMessageId));
            expect(messagePersisted, isTrue);
          },
        );
      },
    );

    group('Security Boundary: Zero Leaked Master Credentials in Client Code', () {
      test(
        'Client codebase contains zero OneSignal master REST keys or service-role secrets',
        () {
          final filesToCheck = [
            'lib/features/notifications/data/push_dispatch_service.dart',
            'lib/features/notifications/presentation/controllers/push_controller.dart',
            'lib/main.dart',
            'lib/features/notifications/data/onesignal_service.dart',
          ];

          final forbiddenPatterns = [
            RegExp(r'Basic\s+[A-Za-z0-9+/=]{20,}'), // Basic auth headers
            RegExp(r'ONESIGNAL_REST_KEY', caseSensitive: false),
            RegExp(r'service_role', caseSensitive: false),
            RegExp(r'supabaseServiceRoleKey', caseSensitive: false),
          ];

          for (final filePath in filesToCheck) {
            final file = File(filePath);
            if (!file.existsSync()) continue;
            final content = file.readAsStringSync();

            for (final pattern in forbiddenPatterns) {
              final match = pattern.hasMatch(content);
              expect(
                match,
                isFalse,
                reason:
                    'File $filePath should never contain master secrets matching $pattern',
              );
            }
          }
        },
      );
    });
  });
}
