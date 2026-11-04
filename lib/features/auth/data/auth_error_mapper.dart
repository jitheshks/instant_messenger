import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized utility for translating authentication exceptions from Supabase
/// into actionable, human-readable error messages for the user interface.
class AuthErrorMapper {
  /// Converts any caught authentication exception into a clean user-facing message.
  static String toUserFriendlyMessage(Object error) {
    if (error is AuthException) {
      return _mapSupabaseAuthException(error);
    }

    if (error is FormatException) {
      return error.message;
    }

    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return 'An unexpected error occurred. Please try again.';
  }

  static String _mapSupabaseAuthException(AuthException e) {
    final msg = e.message.toLowerCase();
    final status = int.tryParse(e.statusCode ?? '') ?? 0;

    if (status == 429 ||
        msg.contains('rate limit') ||
        msg.contains('over_sms_send_rate_limit') ||
        msg.contains('too many requests')) {
      return 'Too many requests. Please wait a moment before requesting another verification code.';
    }

    if (msg.contains('invalid token') ||
        msg.contains('token has expired') ||
        msg.contains('otp expired') ||
        msg.contains('invalid otp')) {
      return 'Invalid or expired verification code. Please check the code and try again.';
    }

    if (msg.contains('invalid phone') || msg.contains('unsupported phone')) {
      return 'Invalid phone number format or unsupported mobile carrier.';
    }

    if (msg.contains('sms provider') || msg.contains('error sending sms')) {
      return 'SMS delivery failed. Please ensure the phone number is active and try again.';
    }

    return e.message;
  }
}
