import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/network/network_diagnostics.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/chats/data/chats_repository.dart';
import 'package:instant_messenger/features/chats/domain/models/chat_summary.dart';
import 'package:instant_messenger/features/chats/presentation/controllers/chats_tab_notifier.dart';
import 'package:instant_messenger/features/chats/presentation/providers/chats_providers.dart';
import 'package:instant_messenger/features/chats/presentation/screens/chats_tab_screen.dart';
import 'package:instant_messenger/features/chats/presentation/widgets/chat_list_item.dart';
import 'package:instant_messenger/features/contacts/presentation/controllers/contacts_data_notifier.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/shared/widgets/states/empty_state_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeConnectivity implements Connectivity {
  List<ConnectivityResult> currentResults = [ConnectivityResult.none];
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

class _FakeChatsRepository extends ChatsRepository {
  List<ChatSummary> summariesToEmit = [];
  Object? errorToEmit;
  int fetchCallCount = 0;
  final StreamController<RealtimeSubscribeStatus> _realtimeController =
      StreamController<RealtimeSubscribeStatus>.broadcast();

  @override
  Stream<RealtimeSubscribeStatus> get onRealtimeStatusChanged =>
      _realtimeController.stream;

  void emitRealtimeStatus(RealtimeSubscribeStatus status) {
    _realtimeController.add(status);
  }

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

  late _FakeConnectivity fakeConnectivity;
  late _FakeChatsRepository fakeRepo;
  late ConnectivityService connectivityService;
  bool isBackendSocketReachable = false;

  final sampleChat = ChatSummary(
    id: 'chat-001',
    lastMessage: 'Hello there!',
    lastTime: DateTime(2026, 11, 3, 10, 0),
    unread: 0,
    muted: false,
    members: const ['user_me', 'user_peer'],
    otherUserId: 'user_peer',
    otherPhoneE164: '+1234567890',
    lastSenderId: 'user_peer',
    lastMessageStatus: 1,
  );

  setUp(() {
    fakeConnectivity = _FakeConnectivity();
    fakeRepo = _FakeChatsRepository();
    isBackendSocketReachable = false;
    connectivityService = ConnectivityService(
      connectivity: fakeConnectivity,
      enableControlledRetries: false,
      networkDiagnostics: NetworkDiagnostics(
        socketTester: (h, p, t) async => isBackendSocketReachable,
      ),
      backendEndpoint: Uri.parse('https://test.supabase.co'),
    );
  });

  tearDown(() {
    connectivityService.dispose();
  });

  Widget buildApp({
    required WidgetTester tester,
    List<dynamic> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        connectivityServiceProvider.overrideWithValue(connectivityService),
        chatsRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserIdProvider.overrideWithValue('user_me'),
        contactsDataControllerProvider.overrideWith(ContactsDataNotifier.new),
        ...overrides.cast(),
      ],
      child: const MaterialApp(
        home: ChatsTabScreen(),
      ),
    );
  }

  group('Stage 2A: Connectivity and Offline Banner Correction Tests', () {
    testWidgets(
      '1. No network interface -> physical offline state ("You are offline")',
      (tester) async {
        fakeConnectivity.currentResults = [ConnectivityResult.none];
        await connectivityService.checkStatus();
        expect(connectivityService.hasNetworkInterface, isFalse);

        fakeRepo.errorToEmit = const SocketException('Network is unreachable');

        await tester.pumpWidget(buildApp(tester: tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // When chats empty and physically offline
        expect(find.byType(EmptyStateView), findsOneWidget);
        expect(find.text("You're offline"), findsOneWidget);
        expect(
          find.text('You are offline. Please check your internet connection.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      },
    );

    testWidgets(
      '2. Wi-Fi available, Supabase unreachable -> backend unavailable ("Connecting to messenger services..."), NOT physical offline',
      (tester) async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        isBackendSocketReachable = false;
        await connectivityService.checkStatus();
        expect(connectivityService.hasNetworkInterface, isTrue);

        // Supabase REST request fails with socket error (e.g. errno 101)
        fakeRepo.errorToEmit =
            const SocketException('Network is unreachable (errno 101)');

        await tester.pumpWidget(buildApp(tester: tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Must display "Connecting to messenger services...", NOT "You are offline"
        expect(find.text("You're offline"), findsNothing);
        expect(
          find.text('You are offline. Please check your internet connection.'),
          findsNothing,
        );
        expect(
          find.text('Connecting to messenger services...'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      '2b. Wi-Fi available, Supabase unreachable WITH cached chats -> banner displays "Connecting to messenger services...", NOT "You are offline"',
      (tester) async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        isBackendSocketReachable = false;
        await connectivityService.checkStatus();
        expect(connectivityService.hasNetworkInterface, isTrue);

        final notifier = ChatsTabNotifier();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectivityServiceProvider
                  .overrideWithValue(connectivityService),
              chatsRepositoryProvider.overrideWithValue(fakeRepo),
              chatsTabControllerProvider.overrideWith(() => notifier),
            ],
            child: const MaterialApp(home: ChatsTabScreen()),
          ),
        );

        // Simulate cached chat present, and Supabase reachability failure
        notifier.state = ChatsTabState(
          chats: [sampleChat],
          isLoading: false,
          isReady: true,
          isBound: true,
          isOffline: false,
          isBackendUnavailable: true,
          errorMessage: 'Connecting to messenger services...',
        );

        await tester.pump();

        expect(find.byType(ChatListItem), findsOneWidget);
        expect(
          find.text('Connecting to messenger services...'),
          findsOneWidget,
        );
        expect(
          find.text('You are offline. Please check your internet connection.'),
          findsNothing,
        );
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Wi-Fi available, Supabase reachable -> connected state, no error banner',
      (tester) async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        isBackendSocketReachable = true;
        await connectivityService.checkStatus();
        expect(connectivityService.hasNetworkInterface, isTrue);

        fakeRepo.summariesToEmit = [sampleChat];
        fakeRepo.errorToEmit = null;

        await tester.pumpWidget(buildApp(tester: tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Conversations displayed without any error or offline banners
        expect(find.byType(ChatListItem), findsOneWidget);
        expect(find.text('+1234567890'), findsOneWidget);
        expect(find.byType(EmptyStateView), findsNothing);
        expect(find.text('Connecting to messenger services...'), findsNothing);
        expect(
          find.text('You are offline. Please check your internet connection.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      '4. Realtime disconnected while REST works -> shows subtle non-blocking synchronization indicator, NOT offline or backend unavailable',
      (tester) async {
        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        isBackendSocketReachable = true;
        await connectivityService.checkStatus();

        fakeRepo.summariesToEmit = [sampleChat];
        fakeRepo.errorToEmit = null;

        final notifier = ChatsTabNotifier();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectivityServiceProvider
                  .overrideWithValue(connectivityService),
              chatsRepositoryProvider.overrideWithValue(fakeRepo),
              chatsTabControllerProvider.overrideWith(() => notifier),
            ],
            child: const MaterialApp(home: ChatsTabScreen()),
          ),
        );

        // Chats are loaded, REST is fine, but Realtime WebSocket drops (channelError)
        notifier.state = ChatsTabState(
          chats: [sampleChat],
          isLoading: false,
          isReady: true,
          isBound: true,
          isOffline: false,
          isBackendUnavailable: false,
          isRealtimeDisconnected: true,
          errorMessage: null,
        );

        await tester.pump();

        // Chats remain fully visible and usable
        expect(find.byType(ChatListItem), findsOneWidget);
        expect(find.text('+1234567890'), findsOneWidget);

        // Subtle synchronization indicator is displayed
        expect(
          find.text('Connecting to Realtime updates...'),
          findsOneWidget,
        );

        // No disruptive error or offline banners
        expect(find.text("You're offline"), findsNothing);
        expect(
          find.text('You are offline. Please check your internet connection.'),
          findsNothing,
        );
        expect(find.text('Connecting to messenger services...'), findsNothing);
      },
    );

    testWidgets(
      '7. Retry action triggers controlled backend reachability check and refresh without reconnect loop',
      (tester) async {
        int probeCount = 0;
        final probeCompleter = Completer<bool>();
        final customConnectivityService = ConnectivityService(
          connectivity: fakeConnectivity,
          networkDiagnostics: NetworkDiagnostics(
            socketTester: (h, p, t) async {
              probeCount++;
              return probeCompleter.future;
            },
          ),
          backendEndpoint: Uri.parse('https://test.supabase.co'),
        );

        fakeConnectivity.currentResults = [ConnectivityResult.wifi];
        await customConnectivityService.checkStatus();
        expect(customConnectivityService.hasNetworkInterface, isTrue);

        fakeRepo.errorToEmit = const SocketException('Connection reset');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectivityServiceProvider
                  .overrideWithValue(customConnectivityService),
              chatsRepositoryProvider.overrideWithValue(fakeRepo),
              currentUserIdProvider.overrideWithValue('user_me'),
              contactsDataControllerProvider
                  .overrideWith(ContactsDataNotifier.new),
            ],
            child: const MaterialApp(home: ChatsTabScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Retry'), findsOneWidget);
        final initialFetchCount = fakeRepo.fetchCallCount;

        // Clear error and provide conversations for retry
        fakeRepo.errorToEmit = null;
        fakeRepo.summariesToEmit = [sampleChat];
        probeCompleter.complete(true);

        // Tap Retry
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Verifies retry initiated controlled check and refresh
        expect(probeCount, greaterThan(0));
        expect(fakeRepo.fetchCallCount, greaterThan(initialFetchCount));
        expect(find.byType(ChatListItem), findsOneWidget);

        customConnectivityService.dispose();
      },
    );
  });
}
