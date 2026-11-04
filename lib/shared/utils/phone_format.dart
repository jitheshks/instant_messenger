import 'package:libphonenumber_plugin/libphonenumber_plugin.dart';

/// Centralized utility to normalize, sanitize, and validate phone numbers in E.164 format.
class PhoneFormat {
  /// Standard ITU-T E.164 pattern: starts with +, followed by 7 to 15 digits (country code + subscriber).
  static final RegExp e164Regex = RegExp(r'^\+[1-9]\d{6,14}$');

  /// Strips whitespace, hyphens, parentheses, and formatting noise from a phone number string.
  static String sanitize(String raw) => raw.replaceAll(RegExp(r'[\s\-()]'), '');

  /// Synchronously checks if the given string represents a valid E.164 phone number.
  static bool isValidE164(String phone) => e164Regex.hasMatch(sanitize(phone));

  /// Normalize to strict E.164 with no spaces, e.g. +911234567890.
  /// Returns null if parsing fails or number is invalid.
  static Future<String?> toE164(String raw, {String iso2 = 'IN'}) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    try {
      // Normalize using libphonenumber
      final normalized = await PhoneNumberUtil.normalizePhoneNumber(s, iso2);
      final cleaned = sanitize(normalized ?? '');

      if (cleaned.isEmpty || !isValidE164(cleaned)) return null;
      return cleaned;
    } catch (_) {
      // Fallback: accept already-canonical inputs like +911234567890
      final guess = sanitize(s);
      if (isValidE164(guess)) return guess;
      return null;
    }
  }
}
