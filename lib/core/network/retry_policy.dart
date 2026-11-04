import 'dart:async';
import 'dart:math';

/// Exception thrown when attempting to automatically retry a non-idempotent operation.
class NonIdempotentRetryException implements Exception {
  final String message;
  const NonIdempotentRetryException([
    this.message =
        'Non-idempotent operation failed and cannot be automatically retried without explicit authorization.',
  ]);

  @override
  String toString() => 'NonIdempotentRetryException: $message';
}

/// Exception thrown when all retry attempts have been exhausted.
class RetryExhaustedException implements Exception {
  final int attempts;
  final Object lastError;
  final StackTrace lastStackTrace;

  const RetryExhaustedException({
    required this.attempts,
    required this.lastError,
    required this.lastStackTrace,
  });

  @override
  String toString() =>
      'RetryExhaustedException: Failed after $attempts attempts. Last error: $lastError';
}

/// Bounded exponential backoff policy with full jitter.
///
/// Follows standard cloud-resilience jitter:
///   `baseDelay = min(maxDelay, initialDelay * (backoffFactor ^ attempt))`
///   `actualDelay = randomFraction * baseDelay`
class RetryPolicy {
  final Duration initialDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final double backoffFactor;
  final double Function() _randomFraction;
  final Future<void> Function(Duration) _sleeper;

  RetryPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
    this.backoffFactor = 2.0,
    Random? random,
    double Function()? randomFraction,
    Future<void> Function(Duration)? sleeper,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
       assert(initialDelay > Duration.zero, 'initialDelay must be positive'),
       assert(
         maxDelay >= initialDelay,
         'maxDelay cannot be smaller than initialDelay',
       ),
       assert(backoffFactor >= 1.0, 'backoffFactor must be at least 1.0'),
       _randomFraction =
           randomFraction ??
           (random != null ? random.nextDouble : Random().nextDouble),
       _sleeper = sleeper ?? Future.delayed;

  /// Calculates the jittered backoff delay for the given 0-based [attempt].
  ///
  /// Attempt 0 is the delay before the 1st retry.
  /// Upper bound follows: `min(maxDelay, initialDelay * (backoffFactor ^ attempt))`.
  /// With full jitter, the actual delay is uniformly distributed in `[0, upperBound]`.
  Duration calculateDelay(int attempt) {
    if (attempt < 0) return Duration.zero;
    final multiplier = pow(backoffFactor, attempt).toDouble();
    final candidateMs = (initialDelay.inMilliseconds * multiplier).round();
    final cappedMs = min(maxDelay.inMilliseconds, candidateMs);
    final fraction = _randomFraction().clamp(0.0, 1.0);
    final jitteredMs = (cappedMs * fraction).round();
    return Duration(milliseconds: jitteredMs);
  }

  /// Calculates the maximum (un-jittered) upper-bound delay cap for the given 0-based [attempt].
  Duration calculateMaxDelay(int attempt) {
    if (attempt < 0) return Duration.zero;
    final multiplier = pow(backoffFactor, attempt).toDouble();
    final candidateMs = (initialDelay.inMilliseconds * multiplier).round();
    return Duration(milliseconds: min(maxDelay.inMilliseconds, candidateMs));
  }

  /// Executes [action] with retry policy and safeguards.
  ///
  /// Safeguards:
  /// - If [isIdempotent] is false, failures are NOT retried unless [allowNonIdempotentRetry] is true.
  /// - [shouldRetry] filters transient vs permanent errors.
  /// - Bounded by [maxAttempts].
  Future<T> execute<T>({
    required Future<T> Function() action,
    bool isIdempotent = false,
    bool allowNonIdempotentRetry = false,
    bool Function(Object error)? shouldRetry,
    void Function(int attempt, Duration delay, Object error)? onRetry,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (error, stackTrace) {
        attempt++;
        if (attempt >= maxAttempts) {
          throw RetryExhaustedException(
            attempts: attempt,
            lastError: error,
            lastStackTrace: stackTrace,
          );
        }

        // Safeguard: Never blindly retry non-idempotent writes
        if (!isIdempotent && !allowNonIdempotentRetry) {
          throw NonIdempotentRetryException(
            'Action failed with error: $error. It is non-idempotent and cannot be retried automatically.',
          );
        }

        if (shouldRetry != null && !shouldRetry(error)) {
          rethrow;
        }

        final delay = calculateDelay(attempt - 1);
        onRetry?.call(attempt, delay, error);
        await _sleeper(delay);
      }
    }
  }
}
