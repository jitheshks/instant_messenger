import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/shared/utils/phone_format.dart';

/// Centralized resolver that resolves a person's display identity according to:
/// 1. If the sender's phone number matches a saved contact, display the saved contact name.
/// 2. If no matching contact exists, display the phone number.
/// 3. If the phone number is unavailable, use a suitable existing fallback without
///    incorrectly preferring the username.
class ContactIdentityResolver {
  /// Matches two phone numbers considering E.164 and suffix matching (e.g. 10 digits).
  static bool matchPhone(String? a, String? b) {
    if (a == null || b == null) return false;
    var cleanA = PhoneFormat.sanitize(a).replaceAll(RegExp(r'[./]'), '');
    var cleanB = PhoneFormat.sanitize(b).replaceAll(RegExp(r'[./]'), '');
    if (cleanA.isEmpty || cleanB.isEmpty) return false;

    // Convert '00' international prefix to '+' (e.g. 0091... -> +91...)
    if (cleanA.startsWith('00')) cleanA = '+${cleanA.substring(2)}';
    if (cleanB.startsWith('00')) cleanB = '+${cleanB.substring(2)}';

    if (cleanA == cleanB) return true;

    final hasPlusA = cleanA.startsWith('+');
    final hasPlusB = cleanB.startsWith('+');
    if (hasPlusA && hasPlusB) {
      // Both specify explicit international country codes and are not equal
      return false;
    }

    // Compare last 10 digits to handle national vs international prefix differences
    final digitsA = cleanA.replaceAll(RegExp(r'\D'), '');
    final digitsB = cleanB.replaceAll(RegExp(r'\D'), '');
    if (digitsA.length >= 10 && digitsB.length >= 10) {
      final suffixA = digitsA.substring(digitsA.length - 10);
      final suffixB = digitsB.substring(digitsB.length - 10);
      return suffixA == suffixB;
    }
    return false;
  }

  /// Resolves identity from a given phone number and contact list.
  /// 1. If the sender's phone number or user ID exists in the recipient's saved contacts, display the saved contact name.
  /// 2. If the sender's phone number does not exist in the recipient's saved contacts, display the sender's phone number.
  /// 3. Never use the sender's username, display_name, or profile name as the fallback.
  /// 4. If the sender's phone number is genuinely unavailable, use a neutral fallback such as "New message".
  static String resolveIdentity({
    required String? phoneE164,
    String? userId,
    Iterable<ContactListEntry>? contacts,
    String fallback = 'New message',
  }) {
    final cleanPhone = phoneE164?.trim();
    final cleanUid = userId?.trim();

    if (contacts != null) {
      for (final entry in contacts) {
        final matchesPhone = cleanPhone != null &&
            cleanPhone.isNotEmpty &&
            entry.phoneE164 != null &&
            matchPhone(entry.phoneE164, cleanPhone);

        final matchesUid = cleanUid != null &&
            cleanUid.isNotEmpty &&
            entry.uid != null &&
            entry.uid == cleanUid;

        if (matchesPhone || matchesUid) {
          // Priority 1: Check saved contact name from device address book
          final savedName = entry.savedName?.trim();
          if (savedName != null && savedName.isNotEmpty) {
            return savedName;
          }
          if (entry.isSaved && entry.displayName.trim().isNotEmpty) {
            return entry.displayName.trim();
          }
          // The contact matches a profile/directory record, but the contact is NOT saved on the device.
          // Never fall back to remote username or profile display_name!
          if (cleanPhone != null && cleanPhone.isNotEmpty) {
            return cleanPhone;
          }
          if (entry.phoneE164 != null && entry.phoneE164!.trim().isNotEmpty) {
            return entry.phoneE164!.trim();
          }
          return fallback;
        }
      }
    }

    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      // Priority 2: No matching saved contact -> display phone number
      return cleanPhone;
    }

    return fallback;
  }
}
