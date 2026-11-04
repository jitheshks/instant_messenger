import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/network/retry_policy.dart';

void main() {
  group('RetryPolicy Unit Tests', () {
    test(
      'calculateMaxDelay follows exponential progression capped at maxDelay',
      () {
        final policy = RetryPolicy(
          initialDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
          maxAttempts: 6,
          backoffFactor: 2.0,
        );

        // Attempt 0: 1s * 2^0 = 1s (1000ms)
        expect(policy.calculateMaxDelay(0), const Duration(milliseconds: 1000));
        // Attempt 1: 1s * 2^1 = 2s (2000ms)
        expect(policy.calculateMaxDelay(1), const Duration(milliseconds: 2000));
        // Attempt 2: 1s * 2^2 = 4s (4000ms)
        expect(policy.calculateMaxDelay(2), const Duration(milliseconds: 4000));
        // Attempt 3: 1s * 2^3 = 8s (8000ms)
        expect(policy.calculateMaxDelay(3), const Duration(milliseconds: 8000));
        // Attempt 4: 1s * 2^4 = 16s (16000ms)
        expect(
          policy.calculateMaxDelay(4),
          const Duration(milliseconds: 16000),
        );
        // Attempt 5: 1s * 2^5 = 32s -> Capped at 30s (30000ms)
        expect(
          policy.calculateMaxDelay(5),
          const Duration(milliseconds: 30000),
        );
      },
    );

    test('calculateDelay applies full jitter fraction properly', () {
      double mockFraction = 0.5;
      final policy = RetryPolicy(
        initialDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 30),
        randomFraction: () => mockFraction,
      );

      // 1000ms * 0.5 = 500ms
      expect(policy.calculateDelay(0), const Duration(milliseconds: 500));

      // With fraction 1.0 (upper bound)
      mockFraction = 1.0;
      expect(policy.calculateDelay(1), const Duration(milliseconds: 2000));

      // With fraction 0.0 (lower bound)
      mockFraction = 0.0;
      expect(policy.calculateDelay(2), Duration.zero);
    });

    test(
      'refuses to automatically retry non-idempotent operations without authorization',
      () async {
        final policy = RetryPolicy(
          initialDelay: const Duration(milliseconds: 10),
          maxAttempts: 3,
          sleeper: (_) async {},
        );

        int attempts = 0;
        Future<void> failingAction() async {
          attempts++;
          throw StateError('Database constraint failed');
        }

        // Default: isIdempotent = false
        await expectLater(
          () => policy.execute(action: failingAction, isIdempotent: false),
          throwsA(isA<NonIdempotentRetryException>()),
        );

        // Must have stopped after first failure (no blind retries)
        expect(attempts, 1);
      },
    );

    test(
      'retries idempotent operations until maxAttempts and throws RetryExhaustedException',
      () async {
        final List<Duration> sleptDelays = [];
        final policy = RetryPolicy(
          initialDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 10),
          maxAttempts: 3,
          randomFraction: () => 1.0, // deterministic max
          sleeper: (d) async => sleptDelays.add(d),
        );

        int attempts = 0;
        Future<void> failingAction() async {
          attempts++;
          throw Exception('Network unreachable');
        }

        await expectLater(
          () => policy.execute(action: failingAction, isIdempotent: true),
          throwsA(isA<RetryExhaustedException>()),
        );

        expect(attempts, 3);
        // Retries happened between attempts 1->2 and 2->3
        expect(sleptDelays.length, 2);
        expect(sleptDelays[0], const Duration(seconds: 1));
        expect(sleptDelays[1], const Duration(seconds: 2));
      },
    );

    test(
      'recovers successfully after transient failures when idempotent',
      () async {
        final List<Duration> sleptDelays = [];
        final policy = RetryPolicy(
          initialDelay: const Duration(milliseconds: 100),
          maxAttempts: 4,
          randomFraction: () => 1.0,
          sleeper: (d) async => sleptDelays.add(d),
        );

        int attempts = 0;
        final result = await policy.execute(
          action: () async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Temporary timeout');
            }
            return 'success';
          },
          isIdempotent: true,
        );

        expect(result, 'success');
        expect(attempts, 3);
        expect(sleptDelays.length, 2);
      },
    );

    test(
      'respects shouldRetry filter and aborts immediately on permanent errors',
      () async {
        final policy = RetryPolicy(
          initialDelay: const Duration(milliseconds: 10),
          maxAttempts: 5,
          sleeper: (_) async {},
        );

        int attempts = 0;
        await expectLater(
          () => policy.execute(
            action: () async {
              attempts++;
              throw ArgumentError('Invalid client payload');
            },
            isIdempotent: true,
            shouldRetry: (error) => error is! ArgumentError,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(attempts, 1);
      },
    );

    test('allows non-idempotent retry only when explicitly opted in', () async {
      final policy = RetryPolicy(
        initialDelay: const Duration(milliseconds: 10),
        maxAttempts: 3,
        sleeper: (_) async {},
      );

      int attempts = 0;
      final result = await policy.execute(
        action: () async {
          attempts++;
          if (attempts < 2) throw Exception('Transient glitch');
          return 'recovered';
        },
        isIdempotent: false,
        allowNonIdempotentRetry: true,
      );

      expect(result, 'recovered');
      expect(attempts, 2);
    });
  });
}
