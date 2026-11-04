import 'package:flutter/foundation.dart';

/// Log severity levels.
enum LogLevel { debug, info, warning, error }

/// Callback signature for intercepting or overriding log messages in tests.
typedef LogPrinter =
    void Function(
      LogLevel level,
      String tag,
      String message,
      Object? error,
      StackTrace? stackTrace,
    );

/// Centralized, security-conscious diagnostic logger for Instant Messenger.
///
/// Features:
/// 1. Uses `debugPrint` in debug mode to prevent log loss from OS buffer throttling.
/// 2. Sanitizes sensitive tokens (Bearer JWTs, OneSignal REST keys, Supabase service keys).
/// 3. Standardizes component tags (`[Auth]`, `[Messaging]`, `[Push]`, `[Sync]`).
/// 4. Disables verbose diagnostic logs in release builds to protect user privacy.
class AppLogger {
  static LogPrinter? _customPrinter;

  /// Sets a custom log printer for testing or telemetry pipelines.
  static void setCustomPrinter(LogPrinter? printer) {
    _customPrinter = printer;
  }

  /// Reset logger to default Flutter `debugPrint` behavior.
  static void reset() {
    _customPrinter = null;
  }

  /// Patterns that should be sanitized to prevent credential leakage.
  static final List<RegExp> _sensitivePatterns = [
    RegExp(
      r'Bearer\s+[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.?[A-Za-z0-9\-_=]*',
      caseSensitive: false,
    ),
    RegExp(r'os_v2_app_[a-z0-9]{30,}', caseSensitive: false),
    RegExp(r'sb_secret_[a-z0-9\-_]{20,}', caseSensitive: false),
    RegExp(r'password["\s:=]+([^\s,]+)', caseSensitive: false),
  ];

  /// Sanitizes messages by masking tokens, secrets, and credentials.
  static String sanitize(String input) {
    var output = input;
    for (final pattern in _sensitivePatterns) {
      output = output.replaceAll(pattern, '[REDACTED_CREDENTIAL]');
    }
    return output;
  }

  /// Logs verbose development diagnostics (debug mode only).
  static void debug(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.debug, tag, message, error, stackTrace);
  }

  /// Logs standard informational events.
  static void info(String message, {String tag = 'App'}) {
    _log(LogLevel.info, tag, message, null, null);
  }

  /// Logs recoverable warnings or non-fatal anomalies.
  static void warning(String message, {String tag = 'App', Object? error}) {
    _log(LogLevel.warning, tag, message, error, null);
  }

  /// Logs fatal or non-recoverable operational failures with diagnostic context.
  static void error(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, tag, message, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String tag,
    String rawMessage,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final sanitizedMessage = sanitize(rawMessage);

    if (_customPrinter != null) {
      _customPrinter!(level, tag, sanitizedMessage, error, stackTrace);
      return;
    }

    if (!kDebugMode && level == LogLevel.debug) {
      return;
    }

    final levelIcon = switch (level) {
      LogLevel.debug => '🔍',
      LogLevel.info => 'ℹ️',
      LogLevel.warning => '⚠️',
      LogLevel.error => '🛑',
    };

    final prefix = '$levelIcon [$tag] $sanitizedMessage';

    if (error != null) {
      debugPrint('$prefix — Error: $error');
      if (stackTrace != null && kDebugMode) {
        debugPrintStack(stackTrace: stackTrace);
      }
    } else {
      debugPrint(prefix);
    }
  }
}
