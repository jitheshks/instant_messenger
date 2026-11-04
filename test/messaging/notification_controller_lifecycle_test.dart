import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:instant_messenger/features/notifications/presentation/controllers/notification_controller.dart';

void main() {
  group('NotificationController & OneSignalService Lifecycle Tests', () {
    setUp(() {
      OneSignalService.pendingNotificationChatId = null;
      OneSignalService.onTap = null;
      OneSignalService.isChatOpenDelegate = null;
      NotificationController.resetForTesting();
    });

    tearDown(() {
      OneSignalService.pendingNotificationChatId = null;
      OneSignalService.onTap = null;
      OneSignalService.isChatOpenDelegate = null;
      NotificationController.resetForTesting();
    });

    test('OneSignalService stores pendingNotificationChatId when onTap is null and consumes cleanly', () {
      expect(OneSignalService.consumePendingNotificationChatId(), isNull);

      OneSignalService.pendingNotificationChatId = 'chat-early-tap';
      expect(OneSignalService.pendingNotificationChatId, equals('chat-early-tap'));

      final consumed = OneSignalService.consumePendingNotificationChatId();
      expect(consumed, equals('chat-early-tap'));
      expect(OneSignalService.pendingNotificationChatId, isNull);
    });

    test('NotificationController.configure drains pending chatId from OneSignalService', () {
      OneSignalService.pendingNotificationChatId = 'chat-cold-start-999';

      String? tappedChatId;
      NotificationController.configure((chatId) {
        tappedChatId = chatId;
      });

      expect(tappedChatId, equals('chat-cold-start-999'));
      expect(OneSignalService.pendingNotificationChatId, isNull);
    });

    test('NotificationController tracks open chat for duplicate prevention', () {
      NotificationController.configure((_) {});

      expect(NotificationController.isChatOpen('chat-1'), isFalse);
      expect(NotificationController.isChatOpen(null), isFalse);

      NotificationController.onChatOpen('chat-1');
      expect(NotificationController.isChatOpen('chat-1'), isTrue);
      expect(NotificationController.isChatOpen('chat-2'), isFalse);

      NotificationController.onChatClose('chat-1');
      expect(NotificationController.isChatOpen('chat-1'), isFalse);
    });

    test('Early notification tap before configure is buffered and drained upon configure', () {
      NotificationController.onNotificationTap('chat-buffered-123');

      String? drainedChatId;
      NotificationController.configure((chatId) {
        drainedChatId = chatId;
      });

      expect(drainedChatId, equals('chat-buffered-123'));
    });

    test('Rapid duplicate notification tap within 1 second is debounced', () {
      var callCount = 0;
      String? lastTappedId;
      NotificationController.configure((chatId) {
        callCount++;
        lastTappedId = chatId;
      });

      NotificationController.onNotificationTap('chat-debounce-test');
      expect(callCount, equals(1));
      expect(lastTappedId, equals('chat-debounce-test'));

      // Immediate second tap for the same chat should be debounced
      NotificationController.onNotificationTap('chat-debounce-test');
      expect(callCount, equals(1));

      // Tap for a different chat goes through immediately
      NotificationController.onNotificationTap('chat-other');
      expect(callCount, equals(2));
      expect(lastTappedId, equals('chat-other'));
    });

    test('Empty or whitespace chatId is safely ignored and not buffered or forwarded', () {
      String? tappedChatId;
      NotificationController.configure((chatId) {
        tappedChatId = chatId;
      });

      NotificationController.onNotificationTap('');
      NotificationController.onNotificationTap('   ');
      NotificationController.onNotificationTap('\t\n');

      expect(tappedChatId, isNull);
      expect(NotificationController.pendingChatId, isNull);
    });

    test('OneSignalService.extractChatIdFromPayload parses chatId, chat_id, and chat keys with trimming', () {
      expect(OneSignalService.extractChatIdFromPayload(null), isNull);
      expect(OneSignalService.extractChatIdFromPayload({}), isNull);
      expect(OneSignalService.extractChatIdFromPayload({'chatId': ''}), isNull);
      expect(OneSignalService.extractChatIdFromPayload({'chatId': '   '}), isNull);

      expect(
        OneSignalService.extractChatIdFromPayload({'chatId': 'chat-100'}),
        equals('chat-100'),
      );
      expect(
        OneSignalService.extractChatIdFromPayload({'chatId': '  chat-101  '}),
        equals('chat-101'),
      );
      expect(
        OneSignalService.extractChatIdFromPayload({'chat_id': 'chat-102'}),
        equals('chat-102'),
      );
      expect(
        OneSignalService.extractChatIdFromPayload({'chat': 'chat-103'}),
        equals('chat-103'),
      );
      // Priority: chatId takes precedence over chat_id
      expect(
        OneSignalService.extractChatIdFromPayload({'chatId': 'primary', 'chat_id': 'fallback'}),
        equals('primary'),
      );
    });
  });

  group('RouterNotifier Pending Notification State Machine Tests', () {
    test('RouterNotifier sets and consumes pendingNotificationChatId cleanly', () {
      final guard = RouterNotifier();
      expect(guard.pendingNotificationChatId, isNull);

      guard.setPendingNotificationChatId('chat-777');
      expect(guard.pendingNotificationChatId, equals('chat-777'));

      final consumed = guard.consumePendingNotificationChatId();
      expect(consumed, equals('chat-777'));
      expect(guard.pendingNotificationChatId, isNull);

      // Second consumption returns null
      expect(guard.consumePendingNotificationChatId(), isNull);
    });

    test('RouterNotifier rejects null, empty, or whitespace pendingNotificationChatId without notifying', () {
      final guard = RouterNotifier();
      var notifyCount = 0;
      guard.addListener(() => notifyCount++);

      guard.setPendingNotificationChatId(null);
      guard.setPendingNotificationChatId('');
      guard.setPendingNotificationChatId('   ');
      guard.setPendingNotificationChatId('\n\t');

      expect(guard.pendingNotificationChatId, isNull);
      expect(notifyCount, equals(0));
    });

    test('RouterNotifier preserves pendingNotificationChatId on reset unless clearPendingNotification: true', () {
      final guard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setPendingNotificationChatId('chat-preserve');

      expect(guard.pendingNotificationChatId, equals('chat-preserve'));

      // Transient unauthenticated transition (e.g. auth stream refresh or token re-read)
      guard.reset(clearPendingNotification: false);
      expect(guard.isAuthed, isFalse);
      expect(guard.bootstrapped, isFalse);
      expect(guard.pendingNotificationChatId, equals('chat-preserve'));

      // Explicit logout
      guard.reset(clearPendingNotification: true);
      expect(guard.pendingNotificationChatId, isNull);
    });
  });
}
