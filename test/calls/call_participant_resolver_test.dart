// test/calls/call_participant_resolver_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/services/call_participant_resolver.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';

void main() {
  group('CallParticipantResolver Unit Tests', () {
    const currentUserId = 'user_me_123';
    const peerUserId = 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc';
    const peerPhone = '+919645905577';
    final now = DateTime(2026, 11, 4, 14, 0, 0);

    final savedContacts = [
      const ContactListEntry(
        uid: peerUserId,
        displayName: 'User A-1',
        savedName: 'User A-1',
        phoneE164: peerPhone,
        isSaved: true,
      ),
    ];

    test('1. Outgoing direct call resolves remote participant ID to receiver, never current user', () {
      final call = CallRecord(
        id: 'c-out',
        chatId: 'chat-1',
        callerId: currentUserId,
        receiverId: peerUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        peerName: 'jithesh', // remote profile display_name
        peerPhone: peerPhone,
      );

      final otherId = CallParticipantResolver.resolveParticipantId(
        call: call,
        currentUserId: currentUserId,
      );

      expect(otherId, equals(peerUserId));
      expect(otherId, isNot(equals(currentUserId)));
    });

    test('2. Incoming direct call resolves remote participant ID to caller, never current user', () {
      final call = CallRecord(
        id: 'c-in',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.video,
        status: CallStatus.missed,
        startedAt: now,
        peerName: 'jithesh',
        peerPhone: peerPhone,
      );

      final otherId = CallParticipantResolver.resolveParticipantId(
        call: call,
        currentUserId: currentUserId,
      );

      expect(otherId, equals(peerUserId));
      expect(otherId, isNot(equals(currentUserId)));
    });

    test('3. Direct call resolves peer display name to saved contact "User A-1", ignoring remote "jithesh"', () {
      final call = CallRecord(
        id: 'c-in-1',
        chatId: 'chat-1',
        callerId: peerUserId,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.missed,
        startedAt: now,
        peerName: 'jithesh', // This was the remote profile display_name in Supabase
        peerPhone: peerPhone,
      );

      final resolvedName = CallParticipantResolver.resolveParticipantName(
        call: call,
        currentUserId: currentUserId,
        contacts: savedContacts,
      );

      // Must strictly resolve to saved name 'User A-1', never remote 'jithesh'
      expect(resolvedName, equals('User A-1'));
      expect(resolvedName, isNot(equals('jithesh')));
      expect(resolvedName, isNot(equals(currentUserId)));
    });

    test('4. Direct call without saved contact falls back to phone number, never remote username', () {
      const unsavedPhone = '+919876543210';
      const unsavedUid = 'user_unsaved_789';
      final call = CallRecord(
        id: 'c-unsaved',
        chatId: 'chat-2',
        callerId: unsavedUid,
        receiverId: currentUserId,
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now,
        peerName: 'stranger_profile_name',
        peerPhone: unsavedPhone,
      );

      final resolvedName = CallParticipantResolver.resolveParticipantName(
        call: call,
        currentUserId: currentUserId,
        contacts: savedContacts, // does not contain unsaved contact
      );

      expect(resolvedName, equals(unsavedPhone));
      expect(resolvedName, isNot(equals('stranger_profile_name')));
    });

    test('5. Group call preserves group title/identity', () {
      final groupCall = CallRecord(
        id: 'c-group',
        chatId: 'group-chat-1',
        callerId: peerUserId,
        callType: CallType.video,
        status: CallStatus.ended,
        startedAt: now,
        isGroup: true,
        peerName: 'Core Engineering Team',
      );

      final resolvedName = CallParticipantResolver.resolveParticipantName(
        call: groupCall,
        currentUserId: currentUserId,
        contacts: savedContacts,
      );

      expect(resolvedName, equals('Core Engineering Team'));
    });
  });
}
