import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/logging/app_logger.dart';

void main() {
  group('AppLogger Unit Tests', () {
    final loggedEntries = <String>[];

    setUp(() {
      loggedEntries.clear();
      AppLogger.setCustomPrinter((level, tag, message, error, stackTrace) {
        loggedEntries.add(
          '[$level][$tag] $message${error != null ? " ($error)" : ""}',
        );
      });
    });

    tearDown(() {
      AppLogger.reset();
    });

    test('Sanitizes Bearer JWT tokens from log messages', () {
      const sensitiveMsg =
          'Authenticated caller with Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.do_not_leak_this';
      final sanitized = AppLogger.sanitize(sensitiveMsg);

      expect(
        sanitized.contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
        isFalse,
      );
      expect(sanitized.contains('[REDACTED_CREDENTIAL]'), isTrue);
    });

    test('Sanitizes OneSignal Master REST key from log messages', () {
      const sensitiveMsg =
          'Dispatched via os_v2_app_abcdefghijklmnopqrstuvwxyz1234567890';
      final sanitized = AppLogger.sanitize(sensitiveMsg);

      expect(sanitized.contains('os_v2_app_'), isFalse);
      expect(sanitized.contains('[REDACTED_CREDENTIAL]'), isTrue);
    });

    test('Logs formatted messages with correct levels and component tags', () {
      AppLogger.info('App bootstrap finished', tag: 'Bootstrap');
      AppLogger.warning('Cache miss, fetching from remote', tag: 'Cache');
      AppLogger.error(
        'Failed to load chats',
        tag: 'Chats',
        error: 'NetworkError',
      );

      expect(loggedEntries.length, equals(3));
      expect(
        loggedEntries[0],
        equals('[LogLevel.info][Bootstrap] App bootstrap finished'),
      );
      expect(
        loggedEntries[1],
        equals('[LogLevel.warning][Cache] Cache miss, fetching from remote'),
      );
      expect(
        loggedEntries[2],
        equals('[LogLevel.error][Chats] Failed to load chats (NetworkError)'),
      );
    });
  });
}
