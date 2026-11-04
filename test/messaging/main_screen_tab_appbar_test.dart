import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/navigation/tab_scaffold.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/calls/presentation/screens/calls_tab.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/presentation/screens/communities_tab.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/shared/widgets/bars/searchable_selectable_app_bar.dart';

class FakeChatsRepository extends ChatsRepository {
  List<ChatSummary> summariesToEmit = [];

  @override
  Stream<List<ChatSummary>> watchUserChats([String? currentUserId]) {
    return Stream.value(summariesToEmit);
  }

  @override
  Future<List<ChatSummary>> fetchUserChats([String? currentUserId]) async {
    return summariesToEmit;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatsRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeChatsRepository();
  });

  Widget buildTestTabApp({
    String initialLocation = '/chats',
    List<dynamic> overrides = const [],
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => TabScaffold(child: child),
          routes: [
            GoRoute(path: '/chats', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/updates', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/communities', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/calls', builder: (_, _) => const SizedBox()),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('user_me'),
        chatsRepositoryProvider.overrideWithValue(fakeRepo),
        contactsDataControllerProvider.overrideWith(ContactsDataNotifier.new),
        ...overrides.cast(),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('Main-Screen Shared AppBar & Navigation Tests', () {
    testWidgets('Only ONE AppBar exists in the widget tree, fixed above PageView', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      // Exactly ONE AppBar exists on the screen (the shared one in TabScaffold)
      expect(find.byType(SearchableSelectableAppBar), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);

      // Verify it is an ancestor of PageView, NOT inside PageView children
      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);

      final appBarInsidePageView = find.descendant(
        of: pageViewFinder,
        matching: find.byType(AppBar),
      );
      expect(appBarInsidePageView, findsNothing);
    });

    testWidgets('Initial tab is Chats with "Chats" title and FAB visible', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsWidgets);
      // FloatingActionButton for new chat is present on Chats tab
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.chat), findsOneWidget);
    });

    testWidgets('Tapping bottom navigation destinations updates AppBar title and active tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      // 1. Initial tab: Chats
      expect(find.widgetWithText(AppBar, 'Chats'), findsOneWidget);

      // Updates tab should be hidden from visible bottom navigation
      expect(find.widgetWithText(NavigationBar, 'Updates'), findsNothing);

      // 2. Tap Communities
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Communities'), findsOneWidget);
      expect(find.byType(CommunitiesTab), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      // 3. Tap Calls
      await tester.tap(find.text('Calls'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Calls'), findsOneWidget);
      expect(find.byType(CallsTab), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      // 4. Tap Chats to return
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Chats'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Swiping PageView synchronizes AppBar title and bottom navigation selection', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Chats'), findsOneWidget);

      // Swipe left from Chats to Communities (Updates is hidden)
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Communities'), findsOneWidget);
      expect(find.byType(CommunitiesTab), findsOneWidget);

      // Swipe left from Communities to Calls
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Calls'), findsOneWidget);
      expect(find.byType(CallsTab), findsOneWidget);

      // Swipe right from Calls back to Communities
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Communities'), findsOneWidget);
      expect(find.byType(CommunitiesTab), findsOneWidget);
    });

    testWidgets('Selection mode on Chats tab updates shared AppBar and hides FAB', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TabScaffold));
      final container = ProviderScope.containerOf(element);

      // Enter selection mode with 2 chats
      container.read(chatsTabSelectionControllerProvider.notifier).toggleMany(['chat-1', 'chat-2']);
      await tester.pumpAndSettle();

      // AppBar now shows selection count and close icon
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      // FAB is hidden during selection mode
      expect(find.byType(FloatingActionButton), findsNothing);

      // Tap close selection icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Chats'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Swiping away from Chats tab clears any active selection mode', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestTabApp());
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TabScaffold));
      final container = ProviderScope.containerOf(element);

      // Enter selection mode
      container.read(chatsTabSelectionControllerProvider.notifier).toggle('chat-1');
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Swipe to Communities
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Selection is cleared and Communities AppBar is displayed
      expect(find.widgetWithText(AppBar, 'Communities'), findsOneWidget);
      expect(container.read(chatsTabSelectionControllerProvider), isEmpty);
    });
  });
}
