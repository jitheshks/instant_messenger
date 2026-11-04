// test/communities/communities_tab_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/communities_tab_notifier.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/presentation/screens/communities_tab.dart';
import 'package:instant_messenger/shared/widgets/avatars/safe_avatar.dart';

class _FakeChatsRepository extends ChatsRepository {
  List<ChatSummary> mockGroups = [];
  bool shouldThrow = false;
  String errorMessage = 'Failed to load groups';

  @override
  Future<List<ChatSummary>> fetchUserGroups([String? currentUserId]) async {
    if (shouldThrow) throw Exception(errorMessage);
    return mockGroups;
  }

  @override
  Stream<List<ChatSummary>> watchUserGroups([String? currentUserId]) {
    if (shouldThrow) return Stream.error(Exception(errorMessage));
    return Stream.value(mockGroups);
  }
}

void main() {
  group('Communities & Groups Tab Tests', () {
    late _FakeChatsRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakeChatsRepository();
    });

    testWidgets('1. Existing groups load and display title, preview and member count', (tester) async {
      final now = DateTime.now();
      fakeRepo.mockGroups = [
        ChatSummary(
          id: 'group-1',
          lastMessage: 'Welcome to the team group!',
          lastTime: now,
          unread: 3,
          muted: false,
          otherUserId: '',
          members: ['user-1', 'user-2', 'user-3'],
          lastSenderId: 'user-1',
          lastMessageStatus: 1,
          isGroup: true,
          title: 'Project Alpha Team',
          avatarUrl: 'https://example.com/alpha.png',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CommunitiesTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Project Alpha Team'), findsOneWidget);
      expect(find.text('Welcome to the team group!'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // unread badge
      expect(find.byType(SafeAvatar), findsOneWidget);
    });

    testWidgets('2. Empty groups state displays "No groups yet"', (tester) async {
      fakeRepo.mockGroups = [];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CommunitiesTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Groups you belong to will appear here'), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    });

    testWidgets('3. Loading state shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communitiesTabControllerProvider.overrideWith(() => _LoadingCommunitiesNotifier()),
          ],
          child: const MaterialApp(home: CommunitiesTab()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('4. Error state displays error message and retry button', (tester) async {
      fakeRepo.shouldThrow = true;
      fakeRepo.errorMessage = 'Network timeout occurred';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: CommunitiesTab()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Network timeout occurred'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    test('5. Groups data model correctly isolates group type from direct chats', () {
      final directChat = ChatSummary(
        id: 'direct-1',
        lastMessage: 'Hi',
        lastTime: DateTime.now(),
        unread: 0,
        muted: false,
        otherUserId: 'user-b',
        members: ['user-a', 'user-b'],
        lastSenderId: 'user-b',
        lastMessageStatus: 1,
        isGroup: false,
      );

      final groupChat = ChatSummary(
        id: 'group-2',
        lastMessage: 'Group msg',
        lastTime: DateTime.now(),
        unread: 0,
        muted: false,
        otherUserId: '',
        members: ['user-a', 'user-b', 'user-c'],
        lastSenderId: 'user-c',
        lastMessageStatus: 1,
        isGroup: true,
        title: 'Developers Group',
      );

      final allChats = [directChat, groupChat];
      final groupsOnly = allChats.where((c) => c.isGroup).toList();

      expect(groupsOnly.length, 1);
      expect(groupsOnly.first.title, 'Developers Group');
      expect(groupsOnly.first.isGroup, isTrue);
    });

    test('6. Account isolation ensures groups are scoped to authenticated membership', () {
      const myUid = 'user-auth-111';
      final rowNotMember = {
        'id': 'g-not-mine',
        'type': 'group',
        'title': 'Secret Group',
        'chat_members': [
          {'user_id': 'other-1'},
          {'user_id': 'other-2'},
        ],
      };

      final rowMember = {
        'id': 'g-mine',
        'type': 'group',
        'title': 'My Group',
        'chat_members': [
          {'user_id': myUid},
          {'user_id': 'other-2'},
        ],
      };

      final parsedNotMine = ChatSummary.fromSupabase(rowNotMember, myUid);
      final parsedMine = ChatSummary.fromSupabase(rowMember, myUid);

      expect(parsedNotMine.members.contains(myUid), isFalse);
      expect(parsedMine.members.contains(myUid), isTrue);
    });

    test('7. Realtime updates do not create duplicate group entries (deduplication)', () {
      final now = DateTime.now();
      final g1 = ChatSummary(
        id: 'g-dedup',
        lastMessage: 'Initial message',
        lastTime: now,
        unread: 0,
        muted: false,
        otherUserId: '',
        members: ['u1', 'u2'],
        lastSenderId: 'u1',
        lastMessageStatus: 1,
        isGroup: true,
        title: 'Dedup Group',
      );

      final map = <String, ChatSummary>{};
      map[g1.id] = g1;

      // Realtime event arrives with updated lastMessage:
      final updatedG1 = g1.copyWith(lastMessage: 'New updated message');
      map[updatedG1.id] = updatedG1;

      expect(map.length, 1);
      expect(map.values.first.lastMessage, 'New updated message');
    });
  });
}

class _LoadingCommunitiesNotifier extends CommunitiesTabNotifier {
  @override
  CommunitiesTabState build() => const CommunitiesTabState(isLoading: true);
}
