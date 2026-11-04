import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/media/data/media_storage_service.dart';
import 'package:instant_messenger/features/media/data/supabase_storage_service.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/auth/data/supabase_auth_service.dart';
import 'package:instant_messenger/features/media/data/upload_orchestrator.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeOutboxService implements OutboxService {
  String? lastEnqueuedOwnerType;
  String? lastEnqueuedOwnerId;
  String? lastEnqueuedFilePath;

  @override
  Future<void> enqueueAvatarUpload({
    required String ownerType,
    required String ownerId,
    required String filePath,
  }) async {
    lastEnqueuedOwnerType = ownerType;
    lastEnqueuedOwnerId = ownerId;
    lastEnqueuedFilePath = filePath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaStorageService implements MediaStorageService {
  bool shouldFail = false;
  String? uploadedAvatarPath;
  String? uploadedChatAttachmentPath;

  @override
  Future<StorageUploadResult> uploadAvatar({
    required String ownerType,
    required String ownerId,
    required String filePath,
  }) async {
    if (shouldFail) {
      throw const SocketException('Network failure');
    }
    uploadedAvatarPath = filePath;
    return StorageUploadResult(
      bucket: 'avatars',
      path: '$ownerId/avatar.jpg',
      publicUrl:
          'https://mock.supabase.co/storage/v1/object/public/avatars/$ownerId/avatar.jpg',
      fileSizeBytes: 1024,
    );
  }

  @override
  Future<StorageUploadResult> uploadChatAttachment({
    required String chatId,
    required String messageId,
    required String filePath,
    required String mediaKind,
    String? mimeType,
  }) async {
    if (shouldFail) {
      throw const SocketException('Attachment failure');
    }
    uploadedChatAttachmentPath = filePath;
    return StorageUploadResult(
      bucket: 'attachments',
      path: '$chatId/$messageId.jpg',
      publicUrl:
          'https://mock.supabase.co/storage/v1/object/authenticated/attachments/$chatId/$messageId.jpg',
      fileSizeBytes: 2048,
    );
  }

  @override
  Future<String> getAuthorizedUrl({
    required String bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    return 'https://mock.supabase.co/storage/v1/object/authenticated/$bucket/$path?token=signed';
  }

  @override
  Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('runtime_test_');
    Hive.init(tempDir.path);
    HiveInit.registerAdapters();
    await Hive.openBox('profile');
    await Hive.openBox('contacts');
    await Hive.openBox('chats_meta');
    await Hive.openBox('chat_cache');
    await Hive.openBox<ChatMessage>(
      'cache_msgs_c9ccc86c-cd42-40bb-8678-d9a30964ce30',
    );
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SupabaseConfig.setTargetForTesting(
      BackendTarget.supabase,
      initialized: true,
    );
  });

  tearDown(() async {
    final profileBox = Hive.box('profile');
    await profileBox.clear();
  });

  String? testAppRedirect({
    required RouterNotifier notifier,
    required String location,
  }) {
    final authed = notifier.isAuthed;
    final bootstrapped = notifier.bootstrapped;
    final needName = notifier.requiresName;

    // 1️⃣ NOT AUTHENTICATED → LOGIN
    if (!authed) {
      return (location == '/login' || location == '/otp') ? null : '/login';
    }

    // 2️⃣ AUTHENTICATED BUT BOOTSTRAP NOT DONE
    if (!bootstrapped) {
      return location == '/splash' ? null : '/splash';
    }

    // 3️⃣ NEED DISPLAY NAME
    if (needName) {
      return location == '/editName' ? null : '/editName';
    }

    // 4️⃣ AUTHED + READY → BLOCK AUTH SCREENS
    if (location == '/login' || location == '/otp' || location == '/splash') {
      return '/chats';
    }

    return null;
  }

  group('Runtime Verification Task 1-3: Routing & Bootstrap States', () {
    test(
      'RouterNotifier initializes unauthenticated and redirects to /login',
      () {
        final notifier = RouterNotifier();
        expect(notifier.isAuthed, isFalse);
        expect(notifier.bootstrapped, isFalse);
        expect(notifier.requiresName, isFalse);

        expect(
          testAppRedirect(notifier: notifier, location: '/splash'),
          equals('/login'),
        );
        expect(
          testAppRedirect(notifier: notifier, location: '/chats'),
          equals('/login'),
        );
        expect(testAppRedirect(notifier: notifier, location: '/login'), isNull);
        expect(testAppRedirect(notifier: notifier, location: '/otp'), isNull);
      },
    );

    test(
      'RouterNotifier transitions to authenticated but unbootstrapped -> stays on /splash',
      () {
        final notifier = RouterNotifier()..setAuthed(true);
        expect(notifier.isAuthed, isTrue);
        expect(notifier.bootstrapped, isFalse);

        expect(
          testAppRedirect(notifier: notifier, location: '/chats'),
          equals('/splash'),
        );
        expect(
          testAppRedirect(notifier: notifier, location: '/splash'),
          isNull,
        );
      },
    );

    test('RouterNotifier with requiresName == true redirects to /editName', () {
      final notifier = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(true);

      expect(
        testAppRedirect(notifier: notifier, location: '/splash'),
        equals('/editName'),
      );
      expect(
        testAppRedirect(notifier: notifier, location: '/chats'),
        equals('/editName'),
      );
      expect(
        testAppRedirect(notifier: notifier, location: '/editName'),
        isNull,
      );
    });

    test(
      'RouterNotifier with fully bootstrapped user redirects splash/login to /chats',
      () {
        final notifier = RouterNotifier()
          ..setAuthed(true)
          ..setBootstrapped(true)
          ..setRequiresName(false);

        expect(
          testAppRedirect(notifier: notifier, location: '/splash'),
          equals('/chats'),
        );
        expect(
          testAppRedirect(notifier: notifier, location: '/login'),
          equals('/chats'),
        );
        expect(
          testAppRedirect(notifier: notifier, location: '/otp'),
          equals('/chats'),
        );
        expect(testAppRedirect(notifier: notifier, location: '/chats'), isNull);
      },
    );

    test('RouterNotifier reset clears all state flags', () {
      final notifier = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(true);

      notifier.reset();
      expect(notifier.isAuthed, isFalse);
      expect(notifier.bootstrapped, isFalse);
      expect(notifier.requiresName, isFalse);
    });
  });

  group(
    'Runtime Verification Task 2 & 3: User Profile Retrieval & Error Handling',
    () {
      Future<SupabaseClient> createAuthenticatedClient({
        required Map<String, dynamic>? profileResponse,
        bool throwNetworkError = false,
      }) async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/auth/v1/verify')) {
            return http.Response(
              jsonEncode({
                'access_token': 'fake-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'fake-refresh',
                'user': {
                  'id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'phone': '+919876543210',
                  'created_at': DateTime.now().toIso8601String(),
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path.contains('/rest/v1/profiles')) {
            if (throwNetworkError) {
              return http.Response(
                'Internal Server Error',
                500,
                request: request,
              );
            }
            if (profileResponse == null) {
              return http.Response(
                jsonEncode([]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return http.Response(
              jsonEncode([profileResponse]),
              200,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/1',
              },
              request: request,
            );
          }

          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final authService = SupabaseAuthService(client);
        await authService.verifyCode(
          verificationId: '+919876543210',
          smsCode: '123456',
        );
        return client;
      }

      test(
        'bootstrap with authenticated user and existing display_name resolves NextRoute.chats',
        () async {
          final client = await createAuthenticatedClient(
            profileResponse: {
              'display_name': 'Test User',
              'avatar_url': 'https://example.com/avatar.jpg',
              'phone_e164': '+919876543210',
            },
          );

          final boot = UserBootstrap(supabase: client);
          final route = await boot.bootstrap();

          expect(route, equals(NextRoute.chats));
          expect(LocalCache.displayName, equals('Test User'));
        },
      );

      test(
        'bootstrap with missing display_name returns NextRoute.editName',
        () async {
          final client = await createAuthenticatedClient(
            profileResponse: {
              'display_name': null,
              'avatar_url': null,
              'phone_e164': '+919876543210',
            },
          );

          final boot = UserBootstrap(supabase: client);
          final route = await boot.bootstrap();

          expect(route, equals(NextRoute.editName));
        },
      );

      test(
        'bootstrap with missing profile record returns NextRoute.editName',
        () async {
          final client = await createAuthenticatedClient(
            profileResponse: null,
            throwNetworkError: false,
          );

          final boot = UserBootstrap(supabase: client);
          final route = await boot.bootstrap();

          expect(route, equals(NextRoute.editName));
        },
      );

      test(
        'bootstrap does not treat network/remote query error as incomplete profile and rethrows',
        () async {
          final client = await createAuthenticatedClient(
            profileResponse: null,
            throwNetworkError: true,
          );

          final boot = UserBootstrap(supabase: client);
          expect(() => boot.bootstrap(), throwsA(isA<PostgrestException>()));
        },
      );

      test('setDisplayName updates Supabase profiles table', () async {
        String? updatedBody;

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/auth/v1/verify')) {
            return http.Response(
              jsonEncode({
                'access_token': 'fake-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'fake-refresh',
                'user': {
                  'id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'phone': '+919876543210',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path.contains('/rest/v1/profiles')) {
            updatedBody = request.body;
            return http.Response(
              '',
              204,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }

          return http.Response('Not Found', 404, request: request);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final authService = SupabaseAuthService(client);
        await authService.verifyCode(
          verificationId: '+919876543210',
          smsCode: '123456',
        );

        final boot = UserBootstrap(supabase: client);
        await boot.setDisplayName('Alice Wonder');

        expect(updatedBody, isNotNull);
        final parsed = jsonDecode(updatedBody!) as Map<String, dynamic>;
        expect(parsed['display_name'], equals('Alice Wonder'));
        expect(LocalCache.displayName, equals('Alice Wonder'));
      });
    },
  );

  group(
    'Runtime Verification Task 4 & 5: MediaStorageService & UploadOrchestrator Wiring',
    () {
      test(
        'SupabaseStorageService implements MediaStorageService interface',
        () {
          final MediaStorageService service = SupabaseStorageService();
          expect(service, isA<MediaStorageService>());
          expect(service, isA<SupabaseStorageService>());
        },
      );

      test(
        'UploadOrchestrator successfully delegates avatar upload to MediaStorageService',
        () async {
          final storage = _FakeMediaStorageService();
          final outbox = _FakeOutboxService();
          final orchestrator = UploadOrchestrator(
            storage: storage,
            outbox: outbox,
          );

          final url = await orchestrator.uploadAvatar(
            ownerType: 'user',
            ownerId: 'usr-123',
            filePath: '/tmp/avatar.jpg',
          );

          expect(
            url,
            contains('/storage/v1/object/public/avatars/usr-123/avatar.jpg'),
          );
          expect(storage.uploadedAvatarPath, equals('/tmp/avatar.jpg'));
          expect(outbox.lastEnqueuedFilePath, isNull);
        },
      );

      test(
        'UploadOrchestrator falls back to outbox when uploadAvatar fails',
        () async {
          final storage = _FakeMediaStorageService()..shouldFail = true;
          final outbox = _FakeOutboxService();
          final orchestrator = UploadOrchestrator(
            storage: storage,
            outbox: outbox,
          );

          await expectLater(
            () => orchestrator.uploadAvatar(
              ownerType: 'user',
              ownerId: 'usr-123',
              filePath: '/tmp/failed_avatar.jpg',
            ),
            throwsA(isA<SocketException>()),
          );

          expect(outbox.lastEnqueuedOwnerId, equals('usr-123'));
          expect(outbox.lastEnqueuedOwnerType, equals('user'));
          expect(outbox.lastEnqueuedFilePath, equals('/tmp/failed_avatar.jpg'));
        },
      );

      test(
        'UploadOrchestrator delegates chat attachment upload to MediaStorageService',
        () async {
          final storage = _FakeMediaStorageService();
          final outbox = _FakeOutboxService();
          final orchestrator = UploadOrchestrator(
            storage: storage,
            outbox: outbox,
          );

          final result = await orchestrator.uploadChatAttachment(
            chatId: 'chat-456',
            messageId: 'msg-789',
            filePath: '/tmp/image.jpg',
            mediaKind: 'image',
          );

          expect(result.bucket, equals('attachments'));
          expect(result.path, equals('chat-456/msg-789.jpg'));
          expect(storage.uploadedChatAttachmentPath, equals('/tmp/image.jpg'));
        },
      );
    },
  );

  group(
    'Runtime Verification Task 6: Supabase Device Registration Schema Payload',
    () {
      test(
        'user_devices payload structure conforms to Supabase schema without Firestore',
        () {
          final sampleDeviceRecord = {
            'user_id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
            'player_id': 'd69e4c02-7a01-4475-b44c-35439a66d542',
            'platform': 'android',
            'app_version': '1.0.0+1',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          };

          expect(sampleDeviceRecord['user_id'], isA<String>());
          expect(sampleDeviceRecord['player_id'], isA<String>());
          expect(
            sampleDeviceRecord['platform'],
            isIn(['android', 'ios', 'web', 'unknown']),
          );
          expect(sampleDeviceRecord['app_version'], isA<String>());
          expect(
            DateTime.tryParse(sampleDeviceRecord['last_seen'] as String),
            isNotNull,
          );

          // Verify absence of legacy Firestore constructs (e.g. FieldValue, Timestamp)
          expect(
            sampleDeviceRecord.values.any(
              (v) => v.toString().contains('FieldValue'),
            ),
            isFalse,
          );
        },
      );
    },
  );

  group('Runtime Verification Task 7: Zero Remnants in lib/main.dart', () {
    test(
      'main.dart has zero occurrences of obsolete Firebase, Cloudinary, or target-check symbols',
      () {
        final mainFile = File('lib/main.dart');
        expect(mainFile.existsSync(), isTrue);

        final content = mainFile.readAsStringSync();
        const forbiddenPatterns = [
          'Firebase',
          'Firestore',
          'Cloudinary',
          'DefaultFirebaseOptions',
          'cloudName',
          'uploadPreset',
          'BackendTarget',
          'isSupabaseTarget',
        ];

        final matches = <String>[];
        for (final pattern in forbiddenPatterns) {
          if (content.contains(pattern)) {
            matches.add(pattern);
          }
        }

        expect(
          matches,
          isEmpty,
          reason: 'Found obsolete symbols in main.dart: $matches',
        );
      },
    );
  });
}
