import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeChatsRepository implements ChatsRepository {
  final _controller = StreamController<List<ChatSummary>>.broadcast();

  void emit(List<ChatSummary> chats) {
    _controller.add(chats);
  }

  @override
  Stream<List<ChatSummary>> watchUserChats([String? currentUserId]) =>
      _controller.stream;

  @override
  Stream<RealtimeSubscribeStatus> get onRealtimeStatusChanged =>
      const Stream.empty();

  @override
  Stream<List<ChatSummary>>? watchLocalChats() => null;

  @override
  RealtimeConnectionManager? get connectionManager => null;

  @override
  Stream<RealtimeConnectionStatus>? get onRealtimeConnectionStatus => null;

  @override
  void attachConnectionManager(RealtimeConnectionManager connectionManager) {}

  @override
  void attachChatsStore(dynamic store) {}

  @override
  Future<void> leaveChat(String chatId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('local_cache_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('profile');
    await Hive.openBox('contacts');
    await Hive.openBox('chats_meta');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await Hive.box('profile').clear();
    await Hive.box('contacts').clear();
    await Hive.box('chats_meta').clear();
    LocalCache.setActiveAccount(null);
  });

  group('LocalCache Multi-Account Isolation Tests (Phase 4.5.1 Hardened)', () {
    test(
      'User A caches profile; User B does not see User A cached profile after logout',
      () async {
        // 1. User A logs in
        LocalCache.setActiveAccount('user_a_uuid');
        await LocalCache.setProfile(
          displayName: 'Alice Cooper',
          bio: 'Hello from Alice',
          phoneE164: '+15551112222',
        );

        expect(LocalCache.displayName, equals('Alice Cooper'));
        expect(LocalCache.bio, equals('Hello from Alice'));
        expect(LocalCache.phoneE164, equals('+15551112222'));

        // 2. User A logs out
        await LocalCache.onSignOut();
        expect(LocalCache.activeAccountId, isNull);
        expect(LocalCache.displayName, isNull);

        // 3. User B logs in
        LocalCache.setActiveAccount('user_b_uuid');
        expect(
          LocalCache.displayName,
          isNull,
          reason: 'User B must not leak User A cached name',
        );
        expect(LocalCache.bio, isNull);
        expect(LocalCache.phoneE164, isNull);

        // 4. User B sets their own profile
        await LocalCache.setProfile(
          displayName: 'Bob Dylan',
          bio: 'The Times They Are A-Changin',
          phoneE164: '+15553334444',
        );

        expect(LocalCache.displayName, equals('Bob Dylan'));

        // 5. User B logs out
        await LocalCache.onSignOut();
        expect(LocalCache.displayName, isNull);

        // 6. User A logs back in -> cached profile restored from disk without network
        LocalCache.setActiveAccount('user_a_uuid');
        expect(
          LocalCache.displayName,
          equals('Alice Cooper'),
          reason: 'User A cached profile must be preserved on disk',
        );
        expect(LocalCache.bio, equals('Hello from Alice'));
        expect(LocalCache.phoneE164, equals('+15551112222'));
      },
    );

    test(
      'LocalCache isolates contacts and chat metadata per account without fallback leakage',
      () async {
        // User A contacts and chats
        LocalCache.setActiveAccount('user_a');
        await LocalCache.setContact('contact_1', {'name': 'Friend A'});
        await LocalCache.setChatMeta('chat_1', {'unread': 5});

        expect(LocalCache.getContact('contact_1')?['name'], equals('Friend A'));
        expect(LocalCache.getChatMeta('chat_1')?['unread'], equals(5));

        // Sign out
        await LocalCache.onSignOut();

        // User B should NOT see User A contact or chat meta even before caching their own
        LocalCache.setActiveAccount('user_b');
        expect(
          LocalCache.getContact('contact_1'),
          isNull,
          reason: 'Must not leak contact_1 from user_a to user_b',
        );
        expect(
          LocalCache.getChatMeta('chat_1'),
          isNull,
          reason: 'Must not leak chat_1 from user_a to user_b',
        );

        await LocalCache.setContact('contact_1', {'name': 'Friend B'});
        expect(LocalCache.getContact('contact_1')?['name'], equals('Friend B'));

        // Switch back to User A -> User A still has their original contact
        LocalCache.setActiveAccount('user_a');
        expect(LocalCache.getContact('contact_1')?['name'], equals('Friend A'));
        expect(LocalCache.getChatMeta('chat_1')?['unread'], equals(5));
      },
    );

    test(
      'Unauthenticated reads return null and do not leak prior state',
      () async {
        LocalCache.setActiveAccount('user_test');
        await LocalCache.setProfile(
          displayName: 'Test User',
          bio: 'Secret Bio',
        );
        await LocalCache.setContact('c1', {'note': 'Secret note'});
        await LocalCache.setChatMeta('ch1', {'topic': 'Secret topic'});

        // Simulate unauthenticated state
        LocalCache.setActiveAccount(null);
        expect(LocalCache.displayName, isNull);
        expect(LocalCache.bio, isNull);
        expect(LocalCache.avatarUrl, isNull);
        expect(LocalCache.phoneE164, isNull);
        expect(LocalCache.getContact('c1'), isNull);
        expect(LocalCache.getChatMeta('ch1'), isNull);
      },
    );

    test(
      'Legacy un-scoped profile data is migrated once and purged from raw keys',
      () async {
        // Simulate legacy install state in Hive
        final profileBox = Hive.box('profile');
        await profileBox.put('display_name', 'Legacy Master');
        await profileBox.put('bio', 'Legacy Bio');
        await profileBox.put('phone_e164', '+19999999999');

        // User logs in for first time after update
        LocalCache.setActiveAccount('migrated_user');
        expect(LocalCache.displayName, equals('Legacy Master'));
        expect(LocalCache.bio, equals('Legacy Bio'));
        expect(LocalCache.phoneE164, equals('+19999999999'));

        // Verify un-scoped raw keys were purged to prevent leakage to future accounts
        expect(profileBox.get('display_name'), isNull);
        expect(profileBox.get('bio'), isNull);
        expect(profileBox.get('phone_e164'), isNull);
        expect(profileBox.get('legacy_migrated_to'), equals('migrated_user'));

        // Another user logging in does not see the migrated legacy data
        LocalCache.setActiveAccount('different_user');
        expect(LocalCache.displayName, isNull);
        expect(LocalCache.bio, isNull);
      },
    );
  });

  group('ChatsTabNotifier Lifecycle & Reset Tests (Phase 4.5 Task 6 / Modern Riverpod)', () {
    test(
      'reset() unbinds notifier, clears chats, and resets ready state',
      () async {
        final repo = _FakeChatsRepository();
        final container = ProviderContainer(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(chatsTabNotifierProvider.notifier);

        final summaries = [
          ChatSummary(
            id: 'chat_1',
            lastMessage: 'Hey there',
            lastTime: DateTime(2026, 1, 1, 10, 0),
            unread: 0,
            muted: false,
            otherUserId: 'user_b',
            members: const ['user_a', 'user_b'],
            lastSenderId: 'user_a',
            lastMessageStatus: 1,
          ),
        ];

        // Bind user
        await notifier.bind('user_a');
        expect(notifier.isBound, isTrue);

        repo.emit(summaries);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.isReady, isTrue);
        expect(notifier.chats.length, equals(1));

        // Reset / unbind on logout
        notifier.reset();
        expect(notifier.isBound, isFalse);
        expect(notifier.isReady, isFalse);
        expect(notifier.chats, isEmpty);

        // Re-bind with user_b
        await notifier.bind('user_b');
        expect(notifier.isBound, isTrue);
        repo.emit([]);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.chats, isEmpty);
      },
    );
  });
}
