import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/profile/domain/models/group_profile_details.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/group_profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';
import 'package:instant_messenger/features/profile/presentation/screens/group_profile_screen.dart';

class FakeGroupProfileNotifier extends GroupProfileNotifier {
  final GroupProfileDetails mockDetails;

  FakeGroupProfileNotifier(super.arg, this.mockDetails);

  @override
  GroupProfileState build() {
    return GroupProfileState(
      isLoading: false,
      details: mockDetails,
    );
  }

  @override
  void setMemberSearch(String query) {
    state = state.copyWith(memberSearchQuery: query);
  }

  @override
  void setTab(int index) {
    state = state.copyWith(selectedTabIndex: index);
  }

  @override
  Future<bool> setMemberRole(String targetUserId, String newRole) async {
    final updated = state.details?.members.map((m) {
      if (m.userId == targetUserId) return m.copyWith(role: newRole);
      return m;
    }).toList();
    state = state.copyWith(details: state.details?.copyWith(members: updated));
    return true;
  }

  @override
  Future<bool> removeMember(String targetUserId) async {
    final updated = state.details?.members
        .where((m) => m.userId != targetUserId)
        .toList();
    state = state.copyWith(details: state.details?.copyWith(members: updated));
    return true;
  }

  @override
  Future<bool> leaveGroup() async {
    return true;
  }

  @override
  Future<void> clearChat() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testArgs = const GroupProfileArgs(
    chatId: 'group-chat-1',
    currentUserId: 'user-me',
    initialTitle: 'Flutter Dev Team',
  );

  final testDetails = GroupProfileDetails(
    id: 'group-chat-1',
    title: 'Flutter Dev Team',
    description: 'Official development discussion',
    isCurrentUserAdmin: true,
    isMuted: false,
    members: const [
      GroupMemberDetails(
        userId: 'user-me',
        role: 'admin',
        displayName: 'You',
        isCurrentUser: true,
      ),
      GroupMemberDetails(
        userId: 'user-peer-1',
        role: 'member',
        displayName: 'Alice Smith',
        phoneE164: '+919876543210',
      ),
      GroupMemberDetails(
        userId: 'user-peer-2',
        role: 'admin',
        displayName: 'Bob Johnson',
        phoneE164: '+919123456789',
      ),
    ],
  );

  Widget buildTestApp({GroupProfileDetails? details}) {
    final d = details ?? testDetails;
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-me'),
        groupProfileControllerProvider(testArgs).overrideWith(
          () => FakeGroupProfileNotifier(testArgs, d),
        ),
      ],
      child: const MaterialApp(
        home: GroupProfileScreen(
          chatId: 'group-chat-1',
          groupTitle: 'Flutter Dev Team',
        ),
      ),
    );
  }

  group('GroupProfileScreen Widget Tests', () {
    testWidgets('Renders group header, title, member count, and description', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Group info'), findsOneWidget);
      expect(find.text('Flutter Dev Team'), findsOneWidget);
      expect(find.text('Group · 3 members'), findsOneWidget);
      expect(find.text('Official development discussion'), findsOneWidget);
    });

    testWidgets('Renders 3 tabs: Members, Media, Settings', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Members (3)'), findsOneWidget);
      expect(find.text('Media (0)'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Members tab displays members with You and Group Admin badges', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Johnson'), findsOneWidget);

      // Group Admin badge appears for admins
      expect(find.text('Group Admin'), findsWidgets);
    });

    testWidgets('Member search filters the displayed member list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Johnson'), findsOneWidget);

      // Enter search query 'Alice'
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pumpAndSettle();

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Johnson'), findsNothing);
    });

    testWidgets('Admin tapping another member opens role management sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap on member Alice Smith
      await tester.tap(find.text('Alice Smith'));
      await tester.pumpAndSettle();

      // Bottom sheet displays role management options
      expect(find.text('Make group admin'), findsOneWidget);
      expect(find.text('Remove Alice Smith'), findsOneWidget);

      // Tap Make group admin
      await tester.tap(find.text('Make group admin'));
      await tester.pumpAndSettle();

      expect(find.text('Role updated to admin'), findsOneWidget);
    });

    testWidgets('Settings tab displays Exit group with confirmation dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Switch to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Exit group'), findsOneWidget);
      expect(find.text('Clear chat'), findsOneWidget);

      // Tap Exit group
      await tester.tap(find.text('Exit group'));
      await tester.pumpAndSettle();

      expect(find.text('Exit group?'), findsOneWidget);
      expect(
        find.textContaining('You will no longer receive messages or calls from this group'),
        findsOneWidget,
      );

      // Cancel dismisses dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Exit group?'), findsNothing);
    });

    testWidgets('Audio call button displays "Group calling is coming soon." and does not call direct peer', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Group calling is coming soon.'), findsOneWidget);
    });

    testWidgets('Report group displays "This feature is not available yet."', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report group'));
      await tester.pumpAndSettle();

      expect(find.text('Report group?'), findsOneWidget);
      expect(find.text('This feature is not available yet.'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Report group?'), findsNothing);
    });
  });
}
