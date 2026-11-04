// lib/features/calls/presentation/utils/call_error_mapper.dart

/// Utility for mapping low-level calling errors and exceptions into
/// friendly, user-facing error messages.
class CallErrorMapper {
  CallErrorMapper._();

  /// Maps an error object or message string to a localized, user-friendly description.
  static String mapError(Object? error, {String? defaultMessage}) {
    final fallback = defaultMessage ??
        'Could not start call. Please check permissions or network connection.';

    if (error == null) return fallback;

    final message = error.toString().toLowerCase();

    if (message.contains('permission') ||
        message.contains('camera') ||
        message.contains('microphone') ||
        message.contains('record_audio')) {
      return 'Camera and microphone permissions are required to place calls.';
    }

    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection') ||
        message.contains('timeout') ||
        message.contains('unreachable') ||
        message.contains('offline')) {
      return 'Network connection issue. Please check your internet connection.';
    }

    if (message.contains('busy') || message.contains('in another call')) {
      return 'The user is currently busy on another call.';
    }

    if (message.contains('declined') || message.contains('rejected')) {
      return 'The call was declined.';
    }

    if (message.contains('zego') ||
        message.contains('token') ||
        message.contains('room')) {
      return 'Could not connect to call service. Please try again later.';
    }

    return fallback;
  }
}
