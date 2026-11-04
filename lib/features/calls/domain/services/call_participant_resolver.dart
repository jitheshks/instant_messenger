// lib/features/calls/domain/services/call_participant_resolver.dart

import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';

/// Pure domain service responsible for determining the remote participant
/// and resolving their display identity for call logs and calling screens.
class CallParticipantResolver {
  const CallParticipantResolver._();

  /// Derives the remote participant ID relative to the current authenticated user.
  /// For 1-on-1 direct calls:
  /// - If current user is caller -> receiverId
  /// - If current user is receiver -> callerId
  static String resolveParticipantId({
    required CallRecord call,
    required String currentUserId,
  }) {
    if (call.isGroup) {
      return '';
    }
    if (call.callerId == currentUserId) {
      return call.receiverId;
    }
    return call.callerId;
  }

  /// Resolves the human-readable display name for the call's remote participant.
  ///
  /// Guarantees:
  /// 1. Group calls preserve group title or 'Group call'.
  /// 2. Direct calls always identify the other participant relative to [currentUserId].
  /// 3. The current authenticated user is never displayed as the other participant.
  /// 4. Prioritizes recipient's saved contacts (e.g. 'User A-1').
  /// 5. If unsaved, falls back to the peer's phone number.
  /// 6. Never arbitrarily falls back to an unverified remote profile display_name (e.g. 'jithesh')
  ///    over the user's saved contact or phone identity.
  static String resolveParticipantName({
    required CallRecord call,
    required String currentUserId,
    Iterable<ContactListEntry>? contacts,
  }) {
    if (call.isGroup) {
      final groupTitle = call.peerName?.trim();
      return (groupTitle != null && groupTitle.isNotEmpty)
          ? groupTitle
          : 'Group call';
    }

    final peerUid = resolveParticipantId(
      call: call,
      currentUserId: currentUserId,
    );

    final fallbackPhone = call.peerPhone?.trim();
    final fallbackString = (fallbackPhone != null && fallbackPhone.isNotEmpty)
        ? fallbackPhone
        : (call.peerName?.trim().isNotEmpty == true
            ? call.peerName!.trim()
            : 'Contact');

    return ContactIdentityResolver.resolveIdentity(
      phoneE164: call.peerPhone,
      userId: peerUid,
      contacts: contacts,
      fallback: fallbackString,
    );
  }
}
