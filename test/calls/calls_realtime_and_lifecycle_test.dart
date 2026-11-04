// ignore_for_file: must_be_immutable

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/network/connectivity_service.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/core/sync/realtime_connection_manager.dart';
import 'package:instant_messenger/features/calls/data/repositories/supabase_calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/models/call_enums.dart';
import 'package:instant_messenger/features/calls/domain/models/call_record.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_call_models.dart';
import 'package:instant_messenger/features/calls/domain/models/zego_token_response.dart';
import 'package:instant_messenger/features/calls/domain/repositories/calls_repository.dart';
import 'package:instant_messenger/features/calls/domain/services/zego_engine_service.dart';
import 'package:instant_messenger/features/calls/presentation/providers/calls_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Mocks & Test Helpers
// ---------------------------------------------------------------------------

class _FakeAuthSession implements Session {
  @override
  String get accessToken => 'mock-jwt-token';
  @override
  String get tokenType => 'bearer';
  @override
  User get user => const User(
        id: 'user-auth-1234',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  final Session _session = _FakeAuthSession();
  @override
  Session? get currentSession => _session;
  @override
  User? get currentUser => _session.user;
}

class _MockRealtimeChannel extends Fake implements RealtimeChannel {
  @override
  final String topic;
  void Function(RealtimeSubscribeStatus status, Object? error)? onSubscribeCallback;
  bool isSubscribed = false;
  bool isRemoved = false;

  _MockRealtimeChannel(this.topic);

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus status, Object? error)? onSubscribe,
    Duration? timeout,
  ]) {
    onSubscribeCallback = onSubscribe;
    isSubscribed = true;
    if (onSubscribe != null) {
      onSubscribe(RealtimeSubscribeStatus.subscribed, null);
    }
    return this;
  }

  @override
  Future<String> unsubscribe([Duration? timeout]) async {
    isSubscribed = false;
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #onPostgresChanges) {
      return this;
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockRealtimeClient extends Fake implements RealtimeClient {
  @override
  bool get isConnected => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect({int? code, String? reason}) async {}
}

class _MockSupabaseClientWithChannels extends Fake implements SupabaseClient {
  final _FakeGoTrueClient _auth = _FakeGoTrueClient();
  final _MockRealtimeClient _realtime = _MockRealtimeClient();
  final Map<String, _MockRealtimeChannel> activeChannels = {};
  List<Map<String, dynamic>> mockCalls = [];

  @override
  GoTrueClient get auth => _auth;

  @override
  RealtimeClient get realtime => _realtime;

  @override
  RealtimeChannel channel(String name, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    final ch = _MockRealtimeChannel(name);
    activeChannels[name] = ch;
    return ch;
  }

  @override
  Future<String> removeChannel(RealtimeChannel channel) async {
    if (channel is _MockRealtimeChannel) {
      channel.isRemoved = true;
      activeChannels.remove(channel.topic);
    }
    return 'ok';
  }

  @override
  SupabaseQueryBuilder from(String table) {
    return _MockQueryBuilder(this);
  }
}

class _MockQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final _MockSupabaseClientWithChannels _client;

  _MockQueryBuilder(this._client);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _MockFilterBuilder(_client);
  }
}

class _MockFilterBuilder extends Fake
    implements
        PostgrestFilterBuilder<List<Map<String, dynamic>>>,
        PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  final _MockSupabaseClientWithChannels _client;
  int _offset = 0;
  int _limit = 50;

  _MockFilterBuilder(this._client);

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> range(int from, int to, {String? referencedTable}) {
    _offset = from;
    _limit = to - from + 1;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) {
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(String column, List<dynamic> values) {
    return this;
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    return _client.mockCalls.skip(_offset).take(_limit).toList();
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) {
    return _execute().then(onValue, onError: onError);
  }
}

class _FakeConnectivityService extends Fake implements ConnectivityService {
  final bool _hasInterface;
  final BackendReachabilityStatus _reachabilityStatus;
  final _interfaceController = StreamController<NetworkInterfaceStatus>.broadcast();
  final _reachabilityController = StreamController<BackendReachabilityStatus>.broadcast();

  _FakeConnectivityService({
    bool hasInterface = true,
    BackendReachabilityStatus reachabilityStatus = BackendReachabilityStatus.reachable,
  })  : _hasInterface = hasInterface,
        _reachabilityStatus = reachabilityStatus;

  @override
  bool get hasNetworkInterface => _hasInterface;

  @override
  bool get isBackendReachable => _reachabilityStatus == BackendReachabilityStatus.reachable;

  @override
  BackendReachabilityStatus get backendReachabilityStatus => _reachabilityStatus;

  @override
  Stream<NetworkInterfaceStatus> get onStatusChanged => _interfaceController.stream;

  @override
  Stream<BackendReachabilityStatus> get onReachabilityChanged => _reachabilityController.stream;
}

// ---------------------------------------------------------------------------
// Fake CallsRepository for Tab & Lifecycle Tests
// ---------------------------------------------------------------------------

class _TestCallsRepository implements CallsRepository {
  List<CallRecord> storedHistory = [];
  List<CallRecord> activeCalls = [];
  final StreamController<List<CallRecord>> historyController =
      StreamController<List<CallRecord>>.broadcast();

  final List<String> leaveCallsRecorded = [];
  final List<String> cancelCallsRecorded = [];
  final List<String> rejoinCallsRecorded = [];
  int initiateCallAttempts = 0;
  Map<String, dynamic> initiateResponse = {'success': true, 'call_id': 'c-new', 'room_id': 'r-new'};
  Map<String, dynamic> rejoinResponse = {'success': true, 'room_id': 'r-test', 'call_id': 'c-test'};

  @override
  void attachConnectionManager(dynamic connectionManager) {}

  @override
  Future<List<CallRecord>> fetchActiveCallsForUser() async => activeCalls;

  @override
  Future<List<CallRecord>> fetchCallHistory({int limit = 50, int offset = 0}) async {
    if (offset >= storedHistory.length) return const [];
    return storedHistory.skip(offset).take(limit).toList();
  }

  @override
  Stream<List<CallRecord>> watchCallHistory() {
    return historyController.stream;
  }

  @override
  Future<Map<String, dynamic>> initiateCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
  }) async {
    initiateCallAttempts++;
    return initiateResponse;
  }

  @override
  Future<Map<String, dynamic>> leaveCall(String callId) async {
    leaveCallsRecorded.add(callId);
    return {'success': true, 'status': 'left'};
  }

  @override
  Future<Map<String, dynamic>> cancelCall(String callId) async {
    cancelCallsRecorded.add(callId);
    return {'success': true, 'status': 'cancelled'};
  }

  @override
  Future<ZegoTokenResponse> getZegoToken({
    String? callId,
    String? roomId,
    int? effectiveTimeInSeconds,
    CallType? callType,
  }) async {
    return const ZegoTokenResponse(
      token: 'tok-123',
      appId: 12345,
      userId: 'user-auth-1234',
      expiresAt: 1999999999,
    );
  }

  @override
  Future<Map<String, dynamic>> acceptCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> rejectCall(String callId) async => {'success': true};
  @override
  Future<Map<String, dynamic>> inviteToCall({required String callId, required List<String> inviteeIds}) async => {};
  @override
  Future<Map<String, dynamic>> rejoinCall(String callId) async {
    rejoinCallsRecorded.add(callId);
    return rejoinResponse;
  }
  @override
  Future<Map<String, dynamic>> heartbeatCall(String callId) async => {'success': true};
  @override
  Future<CallRecord?> getCallById(String callId) async => null;
  @override
  Future<Map<String, dynamic>> timeoutCall(String callId) async => {};
  @override
  Future<List<CallRecord>> fetchCallsForChat(String chatId) async => [];
  @override
  Stream<List<CallRecord>> watchCallsForChat(String chatId) => const Stream.empty();
}

class _TestZegoEngineService implements ZegoEngineService {
  @override
  bool isInitialized = false;
  ZegoCallSession _currentSession = ZegoCallSession.initial();
  final _sessionController = StreamController<ZegoCallSession>.broadcast();
  final _tokenExpiryController = StreamController<int>.broadcast();

  void setSession(ZegoCallSession session) {
    _currentSession = session;
    _sessionController.add(session);
  }

  @override
  ZegoCallSession get currentSession => _currentSession;
  @override
  Stream<ZegoCallSession> get sessionStream => _sessionController.stream;
  @override
  Stream<int> get tokenWillExpireStream => _tokenExpiryController.stream;

  @override
  Future<void> initializeEngine({
    required int appId,
    ZegoCallScenario scenario = ZegoCallScenario.standardCall,
  }) async {
    isInitialized = true;
  }
  @override
  Future<void> joinRoom({
    required String callId,
    required String roomId,
    required String userId,
    required String userName,
    required String token,
    required CallType callType,
  }) async {
    setSession(_currentSession.copyWith(
      callId: callId,
      roomId: roomId,
      connectionState: ZegoRoomConnectionState.connected,
    ));
  }
  @override
  Future<void> leaveRoom() async {
    setSession(ZegoCallSession.initial());
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'requestPermissions') {
          final List<dynamic> permissions = methodCall.arguments as List<dynamic>;
          final Map<int, int> result = {};
          for (final p in permissions) {
            result[p as int] = 1; // PermissionStatus.granted
          }
          return result;
        }
        if (methodCall.method == 'checkPermissionStatus') {
          return 1; // PermissionStatus.granted
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      null,
    );
  });
  group('Phase 4 — Priority 1: Realtime Connection Integration Tests', () {
    late _MockSupabaseClientWithChannels mockSupabase;
    late _FakeConnectivityService connectivity;
    late RealtimeConnectionManager rcm;
    late SupabaseCallsRepository callsRepo;

    setUp(() {
      mockSupabase = _MockSupabaseClientWithChannels();
      connectivity = _FakeConnectivityService();
      rcm = RealtimeConnectionManager(
        accountId: 'test-account',
        supabaseClient: mockSupabase,
        connectivityService: connectivity,
        socketConnectedChecker: () => true,
      );
      callsRepo = SupabaseCallsRepository(
        mockSupabase,
        connectionManager: rcm,
      );
    });

    tearDown(() async {
      await rcm.stop();
    });

    test('watchCallHistory registers channel, reports status, and unregisters on cancel', () async {
      final stream = callsRepo.watchCallHistory();
      final sub = stream.listen((_) {});

      // Allow subscription setup microtask
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final expectedTopic = 'call_history:user-auth-1234';
      expect(mockSupabase.activeChannels.containsKey(expectedTopic), isTrue);

      final ch = mockSupabase.activeChannels[expectedTopic]!;
      expect(ch.isSubscribed, isTrue);

      // Cancel subscription
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ch.isRemoved, isTrue);
    });

    test('watchCallsForChat registers chat_calls channel and unregisters on cancel', () async {
      final stream = callsRepo.watchCallsForChat('chat-abc-123');
      final sub = stream.listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 10));

      const expectedTopic = 'chat_calls:chat-abc-123';
      expect(mockSupabase.activeChannels.containsKey(expectedTopic), isTrue);

      final ch = mockSupabase.activeChannels[expectedTopic]!;
      expect(ch.isSubscribed, isTrue);

      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ch.isRemoved, isTrue);
    });

    test('watchCallHistory triggers REST catch-up when RealtimeConnectionManager reconnects', () async {
      mockSupabase.mockCalls = [
        {
          'id': 'call-1',
          'chat_id': 'chat-1',
          'caller_id': 'user-auth-1234',
          'call_type': 'audio',
          'status': 'ended',
          'started_at': '2026-11-04T00:00:00Z',
        }
      ];

      final emittedBatches = <List<CallRecord>>[];
      final sub = callsRepo.watchCallHistory().listen(emittedBatches.add);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emittedBatches.isNotEmpty, isTrue);

      // Add a newly caught-up call to database
      mockSupabase.mockCalls.add({
        'id': 'call-2',
        'chat_id': 'chat-1',
        'caller_id': 'user-auth-1234',
        'call_type': 'video',
        'status': 'ended',
        'started_at': '2026-11-04T01:00:00Z',
      });

      // Simulate Realtime reconnection event
      await rcm.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emittedBatches.last.any((c) => c.id == 'call-2'), isTrue);

      await sub.cancel();
    });
  });

  group('Phase 4.1 Hardened — Call Recovery Safety & Lifecycle Tests', () {
    late _MockSupabaseClientWithChannels mockSupabase;
    late _TestCallsRepository testRepo;
    late _TestZegoEngineService testEngine;
    late ProviderContainer container;

    setUp(() {
      mockSupabase = _MockSupabaseClientWithChannels();
      testRepo = _TestCallsRepository();
      testEngine = _TestZegoEngineService();
      container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockSupabase),
          callsRepositoryProvider.overrideWithValue(testRepo),
          zegoEngineServiceProvider.overrideWithValue(testEngine),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Scenario 1: Multi-device — does NOT terminate ongoing call on second device when local engine is idle', () async {
      final now = DateTime.now();
      testRepo.activeCalls = [
        CallRecord(
          id: 'active-call-device-a',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-other',
          callType: CallType.audio,
          status: CallStatus.connected, // Ongoing on Device A
          startedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];

      // Device B runs recovery with idle local engine
      final controller = container.read(callControllerProvider.notifier);
      await controller.recoverAbandonedActiveCalls();

      // Device B MUST NOT terminate Device A's legitimate ongoing call
      expect(testRepo.leaveCallsRecorded, isEmpty);
      expect(testRepo.cancelCallsRecorded, isEmpty);
    });

    test('Scenario 2: Caller resumes app while legitimate outgoing call is ringing — does NOT cancel call', () async {
      final now = DateTime.now();
      testRepo.activeCalls = [
        CallRecord(
          id: 'ringing-call-caller',
          chatId: 'chat-1',
          callerId: 'user-auth-1234', // Local user is caller
          receiverId: 'user-other',
          callType: CallType.video,
          status: CallStatus.ringing,
          startedAt: now.subtract(const Duration(seconds: 15)),
        ),
      ];

      final controller = container.read(callControllerProvider.notifier);
      await controller.recoverAbandonedActiveCalls();

      // Ringing call must NOT be cancelled prematurely; caller is legitimately waiting for answer
      expect(testRepo.cancelCallsRecorded, isEmpty);
      expect(testRepo.leaveCallsRecorded, isEmpty);
    });

    test('Scenario 3: Callee resumes app while legitimate incoming call is ringing — does NOT touch call', () async {
      final now = DateTime.now();
      testRepo.activeCalls = [
        CallRecord(
          id: 'incoming-ringing-callee',
          chatId: 'chat-1',
          callerId: 'user-other',
          receiverId: 'user-auth-1234',
          callType: CallType.audio,
          status: CallStatus.ringing,
          startedAt: now.subtract(const Duration(seconds: 10)),
        ),
      ];

      final controller = container.read(callControllerProvider.notifier);
      await controller.recoverAbandonedActiveCalls();

      expect(testRepo.leaveCallsRecorded, isEmpty);
      expect(testRepo.cancelCallsRecorded, isEmpty);
    });

    test('Scenario 4 & 6: App resumes during temporary network disconnect / reconnection — call preserved', () async {
      final now = DateTime.now();
      testRepo.activeCalls = [
        CallRecord(
          id: 'reconnecting-call',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-other',
          callType: CallType.audio,
          status: CallStatus.connected,
          startedAt: now.subtract(const Duration(minutes: 2)),
        ),
      ];

      // Local session indicates reconnecting/idle during socket reconnect
      final controller = container.read(callControllerProvider.notifier);
      await controller.recoverAbandonedActiveCalls();

      expect(testRepo.leaveCallsRecorded, isEmpty);
      expect(testRepo.cancelCallsRecorded, isEmpty);
    });

    test('Scenario 5: RTC initialization in progress — aborts recovery check and does NOT query repo', () async {
      // Simulate engine in the process of connecting/initializing
      testEngine.setSession(const ZegoCallSession(
        callId: 'call-initializing-1',
        roomId: 'room-init',
        connectionState: ZegoRoomConnectionState.connecting,
      ));

      final controller = container.read(callControllerProvider.notifier);
      await controller.recoverAbandonedActiveCalls();

      expect(testRepo.leaveCallsRecorded, isEmpty);
      expect(testRepo.cancelCallsRecorded, isEmpty);
    });

    test('Scenario 7: Concurrent recovery attempts by two devices — safe and non-destructive', () async {
      final now = DateTime.now();
      testRepo.activeCalls = [
        CallRecord(
          id: 'shared-active-call',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-other',
          callType: CallType.audio,
          status: CallStatus.connected,
          startedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ];

      final containerDevice2 = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockSupabase),
          callsRepositoryProvider.overrideWithValue(testRepo),
          zegoEngineServiceProvider.overrideWithValue(testEngine),
        ],
      );

      final controller1 = container.read(callControllerProvider.notifier);
      final controller2 = containerDevice2.read(callControllerProvider.notifier);

      // Simultaneous recovery execution across two devices
      await Future.wait([
        controller1.recoverAbandonedActiveCalls(),
        controller2.recoverAbandonedActiveCalls(),
      ]);

      expect(testRepo.leaveCallsRecorded, isEmpty);
      expect(testRepo.cancelCallsRecorded, isEmpty);

      containerDevice2.dispose();
    });

    test('Conflict handling: startOutgoingCall does NOT hijack or terminate existing call in chat', () async {
      final conflictRepo = _ConflictCallsRepository();
      final testContainer = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockSupabase),
          callsRepositoryProvider.overrideWithValue(conflictRepo),
          zegoEngineServiceProvider.overrideWithValue(testEngine),
        ],
      );

      final ok = await testContainer.read(callControllerProvider.notifier).startOutgoingCall(
        chatId: 'chat-test-1',
        callType: CallType.audio,
        inviteeIds: ['user-other'],
      );

      // Must fail safely without attempting destructive takeover
      expect(ok, isFalse);
      expect(conflictRepo.leaveCallsRecorded, isEmpty);
      expect(conflictRepo.initiateAttempts, equals(1));
      expect(
        testContainer.read(callControllerProvider).errorMessage,
        contains('Another call is already in progress in this chat.'),
      );

      testContainer.dispose();
    });

    test('Rejoin capability: rejoinActiveCall connects to active ongoing call safely', () async {
      testRepo.rejoinResponse = {
        'success': true,
        'call_id': 'ongoing-call-rejoin',
        'room_id': 'room-authoritative-rejoin',
        'call_type': 'audio',
      };

      final controller = container.read(callControllerProvider.notifier);
      final success = await controller.rejoinActiveCall(
        callId: 'ongoing-call-rejoin',
        callType: CallType.audio,
      );

      expect(success, isTrue);
      expect(testRepo.rejoinCallsRecorded, contains('ongoing-call-rejoin'));
      expect(testEngine.isInitialized, isTrue);
      expect(testEngine.currentSession.callId, equals('ongoing-call-rejoin'));
    });
  });

  group('Phase 4 — Priority 3: Call-History Continuity & Bounded Pagination', () {
    late _TestCallsRepository testRepo;
    late ProviderContainer container;

    setUp(() {
      testRepo = _TestCallsRepository();
      container = ProviderContainer(
        overrides: [
          callsRepositoryProvider.overrideWithValue(testRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('CallsTabNotifier initial load loads calls and sets pagination state', () async {
      final now = DateTime.now();
      final initialCalls = List.generate(
        15,
        (i) => CallRecord(
          id: 'call-$i',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-$i',
          callType: CallType.audio,
          status: CallStatus.ended,
          startedAt: now.subtract(Duration(minutes: i)),
        ),
      );

      final notifier = container.read(callsTabNotifierProvider.notifier);
      expect(notifier, isNotNull);
      testRepo.historyController.add(initialCalls);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(callsTabNotifierProvider);
      expect(state.isLoading, isFalse);
      expect(state.calls.length, equals(15));
      expect(state.hasMore, isFalse); // < pageSize (30)
      expect(state.nextOffset, equals(15));
    });

    test('loadOlder loads subsequent page and deduplicates records', () async {
      final now = DateTime.now();
      // Setup 50 calls in stored history
      testRepo.storedHistory = List.generate(
        50,
        (i) => CallRecord(
          id: 'call-$i',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-$i',
          callType: CallType.audio,
          status: CallStatus.ended,
          startedAt: now.subtract(Duration(minutes: i)),
        ),
      );

      final notifier = container.read(callsTabNotifierProvider.notifier);
      // Emit first page of 30 items
      testRepo.historyController.add(testRepo.storedHistory.take(30).toList());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      var state = container.read(callsTabNotifierProvider);
      expect(state.calls.length, equals(30));
      expect(state.hasMore, isTrue);
      expect(state.nextOffset, equals(30));

      // Trigger loadOlder
      await notifier.loadOlder();

      state = container.read(callsTabNotifierProvider);
      expect(state.calls.length, equals(50));
      expect(state.nextOffset, equals(50));
      expect(state.hasMore, isFalse); // 20 items returned (< 30), so hasMore is false
    });

    test('Realtime event deduplication merges without duplicates and preserves older paginated calls', () async {
      final now = DateTime.now();
      final page1 = List.generate(
        30,
        (i) => CallRecord(
          id: 'call-$i',
          chatId: 'chat-1',
          callerId: 'user-auth-1234',
          receiverId: 'user-$i',
          callType: i.isEven ? CallType.audio : CallType.video,
          status: CallStatus.ended,
          startedAt: now.subtract(Duration(minutes: i + 1)),
        ),
      );

      final notifier = container.read(callsTabNotifierProvider.notifier);
      testRepo.historyController.add(page1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Older call previously loaded via pagination
      final oldCall = CallRecord(
        id: 'call-old-99',
        chatId: 'chat-1',
        callerId: 'user-auth-1234',
        receiverId: 'user-99',
        callType: CallType.audio,
        status: CallStatus.ended,
        startedAt: now.subtract(const Duration(days: 3)),
      );

      // Stored history contains page1 items followed by oldCall
      testRepo.storedHistory = [...page1, oldCall];
      await notifier.loadOlder();

      var state = container.read(callsTabNotifierProvider);
      expect(state.calls.map((c) => c.id).toList(), contains('call-old-99'));

      // Now a Realtime update arrives with an updated status for call-1,
      // and a brand new call-new-0
      final updatedCall1 = page1[1].copyWith(durationSeconds: 300);
      final newCall0 = CallRecord(
        id: 'call-new-0',
        chatId: 'chat-1',
        callerId: 'user-auth-1234',
        receiverId: 'user-0',
        callType: CallType.audio,
        status: CallStatus.connected,
        startedAt: now,
      );

      testRepo.historyController.add([newCall0, updatedCall1]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      state = container.read(callsTabNotifierProvider);

      // Verify no duplicate IDs
      final ids = state.calls.map((c) => c.id).toList();
      expect(ids.toSet().length, equals(ids.length));

      // Verify new call is at top (newest startedAt)
      expect(state.calls.first.id, equals('call-new-0'));

      // Verify updated record preserved durationSeconds
      expect(state.calls.firstWhere((c) => c.id == 'call-1').durationSeconds, equals(300));

      // Verify older paginated call was NOT dropped!
      expect(ids, contains('call-old-99'));
    });
  });
}

class _ConflictCallsRepository extends _TestCallsRepository {
  int initiateAttempts = 0;

  @override
  Future<Map<String, dynamic>> initiateCall({
    required String chatId,
    required CallType callType,
    required List<String> inviteeIds,
  }) async {
    initiateAttempts++;
    return {
      'success': false,
      'error': 'call_in_progress',
      'existing_call_id': 'active-call-in-chat-999',
    };
  }
}
