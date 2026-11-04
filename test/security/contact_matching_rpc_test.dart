import 'package:flutter_test/flutter_test.dart';

/// Simulates the server-side logic specified in public.match_contacts RPC
/// to ensure test coverage of validation rules, limits, and sanitization.
class ContactMatchValidator {
  static const int maxBatchSize = 200;
  static const int maxRequestsPerWindow = 10;
  static const Duration rateLimitWindow = Duration(minutes: 15);

  final Map<String, List<DateTime>> _requestLog = {};

  List<String> normalizeAndFilter(List<String>? inputNumbers) {
    if (inputNumbers == null || inputNumbers.isEmpty) {
      return [];
    }

    if (inputNumbers.length > maxBatchSize) {
      throw ArgumentError.value(
        inputNumbers.length,
        'phoneNumbers',
        'Batch limit exceeded: maximum $maxBatchSize phone numbers allowed per match request',
      );
    }

    final e164Regex = RegExp(r'^\+[1-9]\d{6,14}$');
    final normalized = <String>[];

    for (final raw in inputNumbers) {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
      if (e164Regex.hasMatch(cleaned)) {
        normalized.add(cleaned);
      }
    }

    return normalized;
  }

  void checkRateLimit(String userId, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    final timestamps = _requestLog.putIfAbsent(userId, () => []);

    // Filter to current window
    timestamps.removeWhere((t) => now.difference(t) > rateLimitWindow);

    if (timestamps.length >= maxRequestsPerWindow) {
      throw StateError(
        'Rate limit exceeded: contact sync is limited to $maxRequestsPerWindow requests per 15 minutes',
      );
    }

    timestamps.add(now);
  }
}

void main() {
  group('Hardened Contact Matching RPC Logic Tests', () {
    late ContactMatchValidator validator;

    setUp(() {
      validator = ContactMatchValidator();
    });

    test('TC-SEC-05: Rejects batch sizes exceeding 200 numbers', () {
      final oversizedList = List.generate(
        201,
        (i) => '+1415555${i.toString().padLeft(4, '0')}',
      );

      expect(
        () => validator.normalizeAndFilter(oversizedList),
        throwsArgumentError,
      );
    });

    test('Accepts valid batches up to 200 numbers', () {
      final validList = List.generate(
        200,
        (i) => '+1415555${i.toString().padLeft(4, '0')}',
      );
      final result = validator.normalizeAndFilter(validList);

      expect(result.length, equals(200));
    });

    test('Sanitizes formatted numbers into pure E.164 strings', () {
      final rawInputs = [
        '+1 (415) 555-2671',
        '+44 20 7946 0958',
        '+91-98765-43210',
        'invalid-phone',
        '12345', // Missing leading '+'
      ];

      final normalized = validator.normalizeAndFilter(rawInputs);

      expect(
        normalized,
        equals(['+14155552671', '+442079460958', '+919876543210']),
      );
    });

    test(
      'TC-SEC-06: Enforces rate limit of 10 requests per 15-minute window',
      () {
        const testUser = 'user-uuid-1234';
        final baseTime = DateTime(2026, 10, 21, 12, 0);

        // First 10 requests within window succeed
        for (int i = 0; i < 10; i++) {
          expect(
            () => validator.checkRateLimit(
              testUser,
              currentTime: baseTime.add(Duration(seconds: i * 10)),
            ),
            returnsNormally,
          );
        }

        // 11th request within window is blocked
        expect(
          () => validator.checkRateLimit(
            testUser,
            currentTime: baseTime.add(const Duration(minutes: 5)),
          ),
          throwsStateError,
        );

        // After 15 minutes, window resets and request succeeds
        expect(
          () => validator.checkRateLimit(
            testUser,
            currentTime: baseTime.add(const Duration(minutes: 16)),
          ),
          returnsNormally,
        );
      },
    );
  });
}
