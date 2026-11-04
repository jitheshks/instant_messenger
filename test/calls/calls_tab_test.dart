// test/calls/calls_tab_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/calls/presentation/controllers/calls_tab_notifier.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:instant_messenger/features/calls/presentation/screens/calls_tab.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';

class _FakeCallsRepository implements CallsRepository {
  List<CallRecord> mockHistory = [];
  bool shouldThrow = false;
  String errorMessage = 'Failed to load calls';

  @override
  Future<List<CallRecord>> fetchCallHistory({int limit = 50, int offset = 0}) async {
    if (shouldThrow) throw Exception(errorMessage);
    if (offset >= mockHistory.length) return const [];
    return mockHistory.skip(offset).take(limit).toList();
  }

  @override
  Stream<List<CallRecord>> watchCallHistory() {
    if (shouldThrow) return Stream.error(Exception(errorMessage));
    return Stream.value(mockHistory);
  }

  @override
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async => const [];
  @override
  Stream<List<CallRecord>> watchCallsForChat(String chatId) => const Stream.empty();
  @override
  Future<Map<String, dynamic>> acceptCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> cancelCall(String callId) async => {};
  @override
  Future<ZegoTokenResponse> getZegoToken({String? callId, String? roomId, int? effectiveTimeInSeconds, CallType? callType}) async =>
      const ZegoTokenResponse(token: 't', appId: 1, userId: 'u', expiresAt: 1);
  @override
  Future<Map<String, dynamic>> initiateCall({required String chatId, required CallType callType, required List<String> inviteeIds}) async => {};
  @override
  Future<Map<String, dynamic>> inviteToCall({required String callId, required List<String> inviteeIds}) async => {};
  @override
  Future<Map<String, dynamic>> leaveCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> rejectCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> rejoinCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) async => {'success': true};
  @override
  Future<CallRecord?> getCallById(String callId) async => null;
  @override
  Future<Map<String, dynamic>> timeoutCall(String callId) async => {};
  @override
  void attachConnectionManager(dynamic connectionManager) {}
  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async => const [];
}

void main() {
  group('Calls Tab Tests', () {
    late _FakeCallsRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakeCallsRepository();
    });

    testWidgets('1. Existing call history loads and renders items', (tester) async {
      final now = DateTime.now();
      fakeRepo.mockHistory = [
        CallRecord(
          id: 'call-1',
          chatId: 'chat-1',
          callerId: 'user-other',
          receiverId: 'user-me',
          callType: CallType.audio,
          status: CallStatus.ended,
          startedAt: now,
          peerName: 'Alice',
          durationSeconds: 120,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
      expect(find.textContaining('02:00'), findsOneWidget);
    });

    testWidgets('2. Empty history displays "No calls yet" empty state', (tester) async {
      fakeRepo.mockHistory = [];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No calls yet'), findsOneWidget);
      expect(find.text('Calls you make or receive will appear here'), findsOneWidget);
      expect(find.byIcon(Icons.call_end_outlined), findsOneWidget);
    });

    testWidgets('3. Missed calls are visually distinguishable with red accent and icon', (tester) async {
      final now = DateTime.now();
      fakeRepo.mockHistory = [
        CallRecord(
          id: 'call-missed',
          chatId: 'chat-2',
          callerId: 'user-other',
          receiverId: 'user-me',
          callType: CallType.audio,
          status: CallStatus.missed,
          startedAt: now,
          peerName: 'Charlie (Missed)',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Charlie (Missed)'), findsOneWidget);
      expect(find.byIcon(Icons.call_missed), findsOneWidget);
    });

    testWidgets('4. Voice and video indicators are correctly differentiated', (tester) async {
      final now = DateTime.now();
      fakeRepo.mockHistory = [
        CallRecord(
          id: 'call-audio',
          chatId: 'chat-3',
          callerId: 'user-me',
          receiverId: 'user-other-1',
          callType: CallType.audio,
          status: CallStatus.ended,
          startedAt: now,
          peerName: 'Voice Contact',
        ),
        CallRecord(
          id: 'call-video',
          chatId: 'chat-4',
          callerId: 'user-me',
          receiverId: 'user-other-2',
          callType: CallType.video,
          status: CallStatus.ended,
          startedAt: now,
          peerName: 'Video Contact',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Voice Contact'), findsOneWidget);
      expect(find.text('Video Contact'), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('5. Loading state shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsTabNotifierProvider.overrideWith(() => _LoadingCallsTabNotifier()),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('6. Error state shows error message and retry button', (tester) async {
      fakeRepo.shouldThrow = true;
      fakeRepo.errorMessage = 'Network connection failed';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Network connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    test('7. Pagination correctly retrieves subsequent pages from repository', () async {
      fakeRepo.mockHistory = List.generate(
        15,
        (i) => CallRecord(
          id: 'call-page-$i',
          chatId: 'chat-$i',
          callerId: 'u1',
          receiverId: 'u2',
          callType: CallType.audio,
          status: CallStatus.ended,
          startedAt: DateTime.now(),
        ),
      );

      final page1 = await fakeRepo.fetchCallHistory(limit: 5, offset: 0);
      expect(page1.length, 5);
      expect(page1.first.id, 'call-page-0');

      final page2 = await fakeRepo.fetchCallHistory(limit: 5, offset: 5);
      expect(page2.length, 5);
      expect(page2.first.id, 'call-page-5');

      final page3 = await fakeRepo.fetchCallHistory(limit: 5, offset: 10);
      expect(page3.length, 5);
      expect(page3.first.id, 'call-page-10');

      final pageEmpty = await fakeRepo.fetchCallHistory(limit: 5, offset: 20);
      expect(pageEmpty, isEmpty);
    });

    testWidgets('8. Calls tab renders saved contact name "User A-1" instead of remote profile name "jithesh"', (tester) async {
      final now = DateTime.now();
      const peerId = 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc';
      const peerPhone = '+919645905577';

      fakeRepo.mockHistory = [
        CallRecord(
          id: 'call-jithesh',
          chatId: 'chat-1',
          callerId: peerId,
          receiverId: 'user-me',
          callType: CallType.audio,
          status: CallStatus.missed,
          startedAt: now,
          peerName: 'jithesh', // Raw remote profile display_name in Supabase
          peerPhone: peerPhone,
        ),
      ];

      final fakeContactsNotifier = _FakeContactsDataNotifier([
        const ContactListEntry(
          uid: peerId,
          displayName: 'User A-1',
          savedName: 'User A-1',
          phoneE164: peerPhone,
          isSaved: true,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callsRepositoryProvider.overrideWithValue(fakeRepo),
            contactsDataControllerProvider.overrideWith(() => fakeContactsNotifier),
          ],
          child: const MaterialApp(home: CallsTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('User A-1'), findsOneWidget);
      expect(find.text('jithesh'), findsNothing);
    });
  });
}

class _LoadingCallsTabNotifier extends CallsTabNotifier {
  @override
  CallsTabState build() => const CallsTabState(isLoading: true);
}

class _FakeContactsDataNotifier extends ContactsDataNotifier {
  final List<ContactListEntry> initialContacts;
  _FakeContactsDataNotifier(this.initialContacts);

  @override
  ContactsDataState build() => ContactsDataState(cachedMatched: initialContacts);
}
