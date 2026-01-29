import 'package:libphonenumber_plugin/libphonenumber_plugin.dart';

/// Utility to normalize phone numbers to E.164 format.
class PhoneFormat {
  static final _ws = RegExp(r'\s'); // matches any whitespace
  static final _e164Digits = RegExp(r'^\+\d{1,15}$'); // E.164 max 15 digits

  /// Normalize to strict E.164 with no spaces, e.g. +911234567890.
  /// Returns null if parsing fails or number is invalid.
  static Future<String?> toE164(String raw, {String iso2 = 'IN'}) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    try {
      // Normalize using libphonenumber
      final normalized = await PhoneNumberUtil.normalizePhoneNumber(s, iso2);
      final cleaned = (normalized ?? '').replaceAll(_ws, '');

      if (cleaned.isEmpty) return null;
      if (!_e164Digits.hasMatch(cleaned)) return null;

      return cleaned;
    } catch (_) {
      // Fallback: accept already-canonical inputs like +911234567890
      final guess = s.replaceAll(_ws, '');
      if (_e164Digits.hasMatch(guess)) return guess;
      return null;
    }
  }
}
