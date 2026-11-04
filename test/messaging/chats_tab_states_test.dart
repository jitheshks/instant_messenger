import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/chats_tab_notifier.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/presentation/screens/chats_tab_screen.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/chat_list_item.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';
import 'package:instant_messenger/shared/widgets/states/empty_state_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeChatsRepository extends ChatsRepository {
  List<ChatSummary> summariesToEmit = [];
  Object? errorToEmit;
  int fetchCallCount = 0;

  @override
  Stream<List<ChatSummary>> watchUserChats([String? currentUserId]) {
    if (errorToEmit != null) {
      return Stream.error(errorToEmit!);
    }
    return Stream.value(summariesToEmit);
  }

  @override
  Future<List<ChatSummary>> fetchUserChats([String? currentUserId]) async {
    fetchCallCount++;
    if (errorToEmit != null) {
      throw errorToEmit!;
    }
    return summariesToEmit;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatsRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeChatsRepository();
  });

  Widget buildTestApp({
    required WidgetTester tester,
    List<dynamic> overrides = const [],
    ContactsDataNotifier Function()? contactsNotifierOverride,
  }) {
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('user_me'),
        chatsRepositoryProvider.overrideWithValue(fakeRepo),
        if (contactsNotifierOverride != null)
          contactsDataControllerProvider.overrideWith(contactsNotifierOverride)
        else
          contactsDataControllerProvider.overrideWith(ContactsDataNotifier.new),
        ...overrides.cast(),
      ],
      child: const MaterialApp(
        home: ChatsTabScreen(),
      ),
    );
  }

  final sampleChat = ChatSummary(
    id: 'chat-001',
    lastMessage: 'Hey there!',
    lastTime: DateTime(2026, 10, 27, 12, 0),
    unread: 2,
    muted: false,
    members: const ['user_me', 'user_peer'],
    otherUserId: 'user_peer',
    otherPhoneE164: '+919876543210',
    lastSenderId: 'user_peer',
    lastMessageStatus: 1,
  );

  group('ChatsTabScreen UI States & Offline-First Verification', () {
    testWidgets('1. Initial loading: displays CircularProgressIndicator when loading and no chats', (tester) async {
      final notifier = ChatsTabNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsTabControllerProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: ChatsTabScreen()),
        ),
      );

      // Default state: isLoading = true, chats = [], errorMessage = null
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(EmptyStateView), findsNothing);
      expect(find.byType(ChatListItem), findsNothing);
    });

    testWidgets('2. Loaded with conversations: displays conversation items', (tester) async {
      fakeRepo.summariesToEmit = [sampleChat];

      await tester.pumpWidget(buildTestApp(tester: tester));
      // Trigger post-frame callback bind
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ChatListItem), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
    });

    testWidgets('3. Loaded with no conversations: displays friendly empty state', (tester) async {
      fakeRepo.summariesToEmit = [];

      await tester.pumpWidget(buildTestApp(tester: tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('No conversations yet'), findsOneWidget);
      expect(
        find.text('Start a conversation with someone to see your messages here.'),
        findsOneWidget,
      );
      expect(find.text('Start a conversation'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('4. Error state: displays error UI and Retry button when query genuinely fails', (tester) async {
      fakeRepo.errorToEmit = const PostgrestException(
        message: 'Internal Database Error',
        code: '500',
      );

      await tester.pumpWidget(buildTestApp(tester: tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('Unable to load chats'), findsOneWidget);
      expect(find.text('Internal Database Error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('5. Offline state with no cached chats: displays You are offline and Retry without infinite spinner', (tester) async {
      fakeRepo.errorToEmit = const SocketException('Connection timed out');

      await tester.pumpWidget(buildTestApp(tester: tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('You are offline. Please check your internet connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('6. Offline state WITH cached chats: displays cached chats plus offline banner with Retry button', (tester) async {
      final notifier = ChatsTabNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsTabControllerProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: ChatsTabScreen()),
        ),
      );

      // Simulate loading cached chats, then receiving an offline error on background refresh
      notifier.state = ChatsTabState(
        chats: [sampleChat],
        isLoading: false,
        isReady: true,
        isBound: true,
        errorMessage: 'You are offline. Please check your internet connection.',
        isOffline: true,
      );

      await tester.pump();

      expect(find.byType(ChatListItem), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('You are offline. Please check your internet connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('7. Refresh / Retry: tapping Retry invokes refresh without infinite spinner', (tester) async {
      fakeRepo.errorToEmit = const SocketException('Network failure');

      await tester.pumpWidget(buildTestApp(tester: tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Retry'), findsOneWidget);

      // Now clear the error and supply conversations
      fakeRepo.errorToEmit = null;
      fakeRepo.summariesToEmit = [sampleChat];

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakeRepo.fetchCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('8. Chat list displays call event preview when latest conversation activity is a call', (tester) async {
      final callPreviewChat = ChatSummary(
        id: 'chat-call-001',
        lastMessage: 'Missed voice call',
        lastTime: DateTime(2026, 11, 4, 15, 30),
        unread: 0,
        muted: false,
        members: const ['user_me', 'user_peer'],
        otherUserId: 'user_peer',
        otherPhoneE164: '+919645905577',
        lastSenderId: 'user_peer',
        lastMessageStatus: 1,
      );

      fakeRepo.summariesToEmit = [callPreviewChat];

      await tester.pumpWidget(buildTestApp(tester: tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Missed voice call'), findsOneWidget);
    });

    testWidgets('9. Chat list consistently displays saved contact name "User A-1" instead of phone number', (tester) async {
      final userChat = ChatSummary(
        id: 'chat-contact-001',
        lastMessage: 'hii',
        lastTime: DateTime(2026, 11, 4, 10, 0),
        unread: 0,
        muted: false,
        members: const ['user_me', 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc'],
        otherUserId: 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc',
        otherPhoneE164: '+919645905577',
        lastSenderId: 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc',
        lastMessageStatus: 1,
      );

      fakeRepo.summariesToEmit = [userChat];

      final fakeContactsNotifier = _FakeContactsNotifier([
        const ContactListEntry(
          uid: 'd1e1ace1-4f3f-4887-a5f5-d210a82c05dc',
          displayName: 'User A-1',
          savedName: 'User A-1',
          phoneE164: '+919645905577',
          isSaved: true,
        ),
      ]);

      await tester.pumpWidget(
        buildTestApp(
          tester: tester,
          contactsNotifierOverride: () => fakeContactsNotifier,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('User A-1'), findsOneWidget);
      expect(find.text('+919645905577'), findsNothing);
    });
  });
}

class _FakeContactsNotifier extends ContactsDataNotifier {
  final List<ContactListEntry> initialContacts;
  _FakeContactsNotifier(this.initialContacts);

  @override
  ContactsDataState build() => ContactsDataState(cachedMatched: initialContacts);
}
