// test/shared/date_formatter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/presentation/utils/call_error_mapper.dart';
import 'package:instant_messenger/shared/utils/date_formatter.dart';

void main() {
  group('DateFormatter Unit Tests', () {
    test('1. formatCallDateTime formats Today correctly', () {
      final now = DateTime(2026, 11, 4, 15, 30);
      final callTime = DateTime(2026, 11, 4, 10, 15);

      final result = DateFormatter.formatCallDateTime(callTime, now);

      expect(result, 'Today, 10:15 AM');
    });

    test('2. formatCallDateTime formats Yesterday correctly', () {
      final now = DateTime(2026, 11, 4, 15, 30);
      final callTime = DateTime(2026, 11, 3, 22, 45);

      final result = DateFormatter.formatCallDateTime(callTime, now);

      expect(result, 'Yesterday, 10:45 PM');
    });

    test('3. formatCallDateTime formats older dates with date and time', () {
      final now = DateTime(2026, 11, 4, 15, 30);
      final callTime = DateTime(2026, 10, 20, 9, 5);

      final result = DateFormatter.formatCallDateTime(callTime, now);

      expect(result, '10/20/2026, 9:05 AM');
    });

    test('4. formatDuration formats seconds into MM:SS and HH:MM:SS', () {
      expect(DateFormatter.formatDuration(0), '00:00');
      expect(DateFormatter.formatDuration(-10), '00:00');
      expect(DateFormatter.formatDuration(45), '00:45');
      expect(DateFormatter.formatDuration(120), '02:00');
      expect(DateFormatter.formatDuration(3665), '01:01:05');
    });
  });

  group('CallErrorMapper Unit Tests', () {
    test('1. Permission errors return clear permission guidance', () {
      final msg = CallErrorMapper.mapError('camera permission denied');
      expect(msg, 'Camera and microphone permissions are required to place calls.');
    });

    test('2. Network and socket errors return internet connection guidance', () {
      final msg = CallErrorMapper.mapError('SocketException: OS error: Network unreachable');
      expect(msg, 'Network connection issue. Please check your internet connection.');
    });

    test('3. Busy user returns busy notification', () {
      final msg = CallErrorMapper.mapError('The peer is in another call right now');
      expect(msg, 'The user is currently busy on another call.');
    });

    test('4. Call declined returns declined notification', () {
      final msg = CallErrorMapper.mapError('Call was rejected by callee');
      expect(msg, 'The call was declined.');
    });

    test('5. Unknown or null errors return friendly fallback message', () {
      expect(
        CallErrorMapper.mapError(null),
        'Could not start call. Please check permissions or network connection.',
      );
      expect(
        CallErrorMapper.mapError('Random unknown error 42'),
        'Could not start call. Please check permissions or network connection.',
      );
    });
  });
}
