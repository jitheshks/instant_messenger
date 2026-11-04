import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/features/contacts/data/acess_service_contact.dart';
import 'package:instant_messenger/features/contacts/data/contact_repository.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/contacts/presentation/screens/contacts_screen.dart';
import 'package:instant_messenger/shared/widgets/bars/search_bar_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.libphonenumber'),
      (call) async {
        if (call.method == 'normalizePhoneNumber') {
          final args = call.arguments as Map?;
          return args?['phoneNumber']?.toString() ??
              args?['phone_number']?.toString();
        }
        return null;
      },
    );
  });

  group('ContactsRepository Resilience & Caching Tests', () {
    test('Unauthenticated users: returns empty list without calling RPC', () async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = ContactsRepository(
        supabaseClient: mockClient,
        currentUserIdProvider: () => null, // Unauthenticated
      );

      final result = await repo.getMatchedContacts();
      expect(result, isEmpty);
      expect(rpcCalls, equals(0));

      final streamResult = await repo.watchMatched().first;
      expect(streamResult, isEmpty);
      expect(rpcCalls, equals(0));
    });

    test('Deduplicates concurrent requests into a single RPC execution', () async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          // Simulate slight network latency
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode([
              {
                'id': 'user-bob-uuid',
                'phone_e164': '+15551234567',
                'display_name': 'Bob',
                'avatar_url': null,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final testRepo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Bob', phoneRaw: '+15551234567'),
        ],
      );

      // Fire 3 calls concurrently
      final futures = await Future.wait([
        testRepo.getMatchedContacts(),
        testRepo.getMatchedContacts(),
        testRepo.getMatchedContacts(),
      ]);

      expect(rpcCalls, equals(1));
      expect(futures[0].length, equals(1));
      expect(futures[1].length, equals(1));
      expect(futures[2].length, equals(1));
      expect(futures[0].first.displayName, equals('Bob'));
    });

    test('Caches successful results and reuses them on subsequent calls', () async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': 'user-alice-uuid',
                'phone_e164': '+15559876543',
                'display_name': 'Alice',
                'avatar_url': null,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Alice', phoneRaw: '+15559876543'),
        ],
      );

      // First call -> hits RPC
      final first = await repo.getMatchedContacts();
      expect(rpcCalls, equals(1));
      expect(first.length, equals(1));
      expect(first.first.displayName, equals('Alice'));

      // Second call -> returns cache, zero new RPC calls
      final second = await repo.getMatchedContacts(forceRefresh: false);
      expect(rpcCalls, equals(1));
      expect(second.length, equals(1));
      expect(identical(first, second), isTrue);

      // Third call via watchMatched -> returns cache, zero new RPC calls
      final third = await repo.watchMatched().first;
      expect(rpcCalls, equals(1));
      expect(third.length, equals(1));
    });

    test('Legitimate manual refresh (forceRefresh: true) triggers fresh RPC', () async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': 'user-alice-uuid',
                'phone_e164': '+15559876543',
                'display_name': 'Alice',
                'avatar_url': null,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Alice', phoneRaw: '+15559876543'),
        ],
      );

      await repo.getMatchedContacts();
      expect(rpcCalls, equals(1));

      // Force refresh executes fresh RPC
      await repo.getMatchedContacts(forceRefresh: true);
      expect(rpcCalls, equals(2));
    });

    test('Rate-limit error: does NOT retry, enters cooldown, and throws friendly exception', () async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode({
              'code': 'P0001',
              'details': null,
              'hint': null,
              'message': 'Rate limit exceeded: contact sync is limited to 10 requests per 15 minutes',
            }),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Charlie', phoneRaw: '+15551112222'),
        ],
      );

      // Attempt matching -> must fail with ContactRateLimitException
      await expectLater(
        repo.getMatchedContacts(),
        throwsA(isA<ContactRateLimitException>().having(
          (e) => e.message,
          'message',
          contains('rate limit reached'),
        )),
      );

      // Crucial: RPC must have been called EXACTLY ONCE (no tight retry loop!)
      expect(rpcCalls, equals(1));
      expect(repo.isRateLimited, isTrue);

      // Immediate subsequent call: blocked by rate-limit cooldown WITHOUT hitting RPC!
      await expectLater(
        repo.getMatchedContacts(),
        throwsA(isA<ContactRateLimitException>()),
      );
      expect(rpcCalls, equals(1)); // Still 1! Zero extra remote calls!
    });

    test('Account switch clears cache (Account Isolation Rule E)', () async {
      int rpcCalls = 0;
      String currentUid = 'user-alice';
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': 'contact-for-$currentUid',
                'phone_e164': '+15559990000',
                'display_name': 'Friend of $currentUid',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserIdProvider: () => currentUid,
        deviceContacts: [
          DeviceContact(savedName: '', phoneRaw: '+15559990000'),
        ],
      );

      // Load for Alice
      final aliceContacts = await repo.getMatchedContacts();
      expect(rpcCalls, equals(1));
      expect(aliceContacts.first.uid, equals('contact-for-user-alice'));
      expect(aliceContacts.first.displayName, equals('Friend of user-alice'));

      // Switch account to Bob
      currentUid = 'user-bob';
      final bobContacts = await repo.getMatchedContacts();
      expect(rpcCalls, equals(2)); // Cache cleared -> fresh fetch for Bob
      expect(bobContacts.first.uid, equals('contact-for-user-bob'));
      expect(bobContacts.first.displayName, equals('Friend of user-bob'));
    });

    test('Transient server errors retry with backoff and succeed if recovered', () async {
      int attempts = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          attempts++;
          if (attempts < 2) {
            return http.Response(
              jsonEncode({'code': '500', 'message': 'Temporary gateway timeout'}),
              500,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'user-1',
                'phone_e164': '+15551234567',
                'display_name': 'Retry User',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Retry User', phoneRaw: '+15551234567'),
        ],
      );

      final result = await repo.getMatchedContacts();
      expect(attempts, equals(2));
      expect(result.first.displayName, equals('Retry User'));
    });
  });

  group('ContactsScreen Widget Lifecycle & Repeated Open Tests', () {
    testWidgets('Opening ContactsScreen does not start new sync if cached', (tester) async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': 'user-1',
                'phone_e164': '+15551234567',
                'display_name': 'Test User',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Test User', phoneRaw: '+15551234567'),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Pre-populate cache or let screen load once
      await repo.getMatchedContacts();
      expect(rpcCalls, equals(1));

      // Pump screen 1st time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Test User'), findsOneWidget);
      expect(rpcCalls, equals(1)); // Reused cache!

      // Rebuild widget / trigger state change (e.g. typing in search)
      container.read(searchBarControllerProvider.notifier).onChanged('Test');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In-memory filter, ZERO new RPC calls!
      expect(find.text('Test User'), findsOneWidget);
      expect(rpcCalls, equals(1));

      // Clear search
      container.read(searchBarControllerProvider.notifier).onChanged('');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(rpcCalls, equals(1));
    });

    testWidgets('Rate limit error displays friendly UI and no raw PostgrestException', (tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'P0001',
            'message': 'Rate limit exceeded: contact sync is limited to 10 requests per 15 minutes',
          }),
          400,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Friend', phoneRaw: '+15559998888'),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Manually trigger load through notifier
      final notifier = container.read(contactsDataControllerProvider.notifier);
      await notifier.loadMatchedContacts();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check friendly UI:
      expect(find.text('Sync Limit Reached'), findsOneWidget);
      expect(find.textContaining('Contact sync rate limit reached'), findsOneWidget);

      // Ensure NO raw PostgrestException or code P0001 exposed to user
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.textContaining('code: P0001'), findsNothing);
    });

    testWidgets('Repeatedly reopening screen reuses cache without additional RPC calls', (tester) async {
      int rpcCalls = 0;
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/rest/v1/rpc/match_contacts')) {
          rpcCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': 'user-1',
                'phone_e164': '+15551234567',
                'display_name': 'Persistent User',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not Found', 404, request: request);
      });

      final mockClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _TestContactsRepository(
        supabaseClient: mockClient,
        currentUserId: 'user-me-123',
        deviceContacts: [
          DeviceContact(savedName: 'Persistent User', phoneRaw: '+15551234567'),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Open screen 1st time (initial load)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Persistent User'), findsOneWidget);
      expect(rpcCalls, equals(1));

      // Close screen (navigate away)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('Another Screen'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Another Screen'), findsOneWidget);

      // Reopen screen 2nd time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Persistent User'), findsOneWidget);
      expect(rpcCalls, equals(1)); // Still 1! Cache reused!

      // Close screen again
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('Another Screen'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Reopen screen 3rd time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContactsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Persistent User'), findsOneWidget);
      expect(rpcCalls, equals(1)); // Still 1! Zero redundant RPC calls!
    });
  });
}

/// Helper test subclass that provides deterministic in-memory device contacts
class _TestContactsRepository extends ContactsRepository {
  _TestContactsRepository({
    required SupabaseClient supabaseClient,
    String? currentUserId,
    String? Function()? currentUserIdProvider,
    List<DeviceContact> deviceContacts = const [],
  }) : super(
          supabaseClient: supabaseClient,
          currentUserIdProvider:
              currentUserIdProvider ?? (() => currentUserId),
          access: _MockContactsAccessService(deviceContacts),
        );
}

class _MockContactsAccessService extends ContactsAccessService {
  final List<DeviceContact> _contacts;
  _MockContactsAccessService(this._contacts);

  @override
  Future<List<DeviceContact>> readPhoneContacts() async => _contacts;
}
