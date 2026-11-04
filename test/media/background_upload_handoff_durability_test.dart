import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:instant_messenger/features/media/data/background_upload_handoff.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackgroundUploadHandoff Durability & Acknowledgement Tests', () {
    test('Standard drain acknowledges and clears processed events', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_1',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/1.jpg',
        fileSizeBytes: 1000,
        kind: 'image',
      );

      final processed = <String>[];
      final events = await BackgroundUploadHandoff.drainForAccount(
        'acc_1',
        onProcessEvent: (event) async {
          processed.add(event.messageId);
        },
      );

      expect(events.length, equals(1));
      expect(processed, contains('msg_1'));

      // Queue must now be empty
      final remaining = await BackgroundUploadHandoff.peekForAccount('acc_1');
      expect(remaining, isEmpty);
    });

    test('Crash / interruption preservation: failing event stays in queue for retry', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_success',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/ok.jpg',
        fileSizeBytes: 1000,
        kind: 'image',
      );
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_fail',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/fail.jpg',
        fileSizeBytes: 2000,
        kind: 'image',
      );

      // Attempt drain where msg_fail throws an exception (simulating crash or transient DB error)
      final events = await BackgroundUploadHandoff.drainForAccount(
        'acc_1',
        onProcessEvent: (event) async {
          if (event.messageId == 'msg_fail') {
            throw Exception('Simulated crash / write error during Hive persist');
          }
        },
      );

      // Only msg_success was acknowledged
      expect(events.length, equals(1));
      expect(events.first.messageId, equals('msg_success'));

      // Peek queue: msg_fail must still be present!
      final remaining = await BackgroundUploadHandoff.peekForAccount('acc_1');
      expect(remaining.length, equals(1));
      expect(remaining.first.messageId, equals('msg_fail'));

      // Next drain succeeds without error
      final retried = await BackgroundUploadHandoff.drainForAccount(
        'acc_1',
        onProcessEvent: (event) async {},
      );
      expect(retried.length, equals(1));
      expect(retried.first.messageId, equals('msg_fail'));

      // Queue is now completely drained
      final finalQueue = await BackgroundUploadHandoff.peekForAccount('acc_1');
      expect(finalQueue, isEmpty);
    });

    test('Concurrently appended events during drain are preserved and not wiped', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_first',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/first.jpg',
        fileSizeBytes: 1000,
        kind: 'image',
      );

      // Simulate a background isolate recording a completion WHILE the main isolate is draining
      final events = await BackgroundUploadHandoff.drainForAccount(
        'acc_1',
        onProcessEvent: (event) async {
          // Concurrently record another upload completion
          await BackgroundUploadHandoff.recordCompletion(
            accountId: 'acc_1',
            messageId: 'msg_concurrent',
            chatId: 'chat_1',
            publicUrl: 'https://example.com/concurrent.jpg',
            fileSizeBytes: 3000,
            kind: 'image',
          );
        },
      );

      expect(events.length, equals(1));
      expect(events.first.messageId, equals('msg_first'));

      // The concurrent event must NOT have been wiped by the first drain!
      final remaining = await BackgroundUploadHandoff.peekForAccount('acc_1');
      expect(remaining.length, equals(1));
      expect(remaining.first.messageId, equals('msg_concurrent'));
    });

    test('Account isolation across accounts A and B', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_A',
        messageId: 'msg_A1',
        chatId: 'chat_A',
        publicUrl: 'https://example.com/a.jpg',
        fileSizeBytes: 100,
        kind: 'image',
      );
      await BackgroundUploadHandoff.recordFailure(
        accountId: 'acc_B',
        messageId: 'msg_B1',
        chatId: 'chat_B',
        errorMessage: 'Network timeout',
      );

      final drainedA = await BackgroundUploadHandoff.drainForAccount('acc_A');
      expect(drainedA.length, equals(1));
      expect(drainedA.first.messageId, equals('msg_A1'));

      // Account B queue is untouched
      final queueB = await BackgroundUploadHandoff.peekForAccount('acc_B');
      expect(queueB.length, equals(1));
      expect(queueB.first.messageId, equals('msg_B1'));
      expect(queueB.first.isSuccess, isFalse);

      final drainedB = await BackgroundUploadHandoff.drainForAccount('acc_B');
      expect(drainedB.length, equals(1));
      expect(drainedB.first.messageId, equals('msg_B1'));
    });

    test('acknowledgeEvents surgically removes specified messageIds', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_1',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/1.jpg',
        fileSizeBytes: 100,
        kind: 'image',
      );
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'acc_1',
        messageId: 'msg_2',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/2.jpg',
        fileSizeBytes: 200,
        kind: 'image',
      );

      await BackgroundUploadHandoff.acknowledgeEvents('acc_1', ['msg_1']);

      final remaining = await BackgroundUploadHandoff.peekForAccount('acc_1');
      expect(remaining.length, equals(1));
      expect(remaining.first.messageId, equals('msg_2'));
    });
  });
}
