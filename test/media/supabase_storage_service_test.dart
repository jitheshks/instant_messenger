import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_messenger/features/media/data/supabase_storage_service.dart';
import 'package:instant_messenger/features/media/data/upload_orchestrator.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_test_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SupabaseStorageService Unit & Validation Tests', () {
    test('uploadAvatar: Rejects non-existent file', () async {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final storage = SupabaseStorageService(mockClient);

      expect(
        () => storage.uploadAvatar(
          ownerType: 'user',
          ownerId: 'user-123',
          filePath: '${tempDir.path}/non_existent_avatar.png',
        ),
        throwsA(isA<FileNotFoundException>()),
      );
    });

    test('uploadAvatar: Rejects empty (0-byte) file', () async {
      final emptyFile = File('${tempDir.path}/empty_avatar.png');
      await emptyFile.writeAsBytes([]);

      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final storage = SupabaseStorageService(mockClient);

      expect(
        () => storage.uploadAvatar(
          ownerType: 'user',
          ownerId: 'user-123',
          filePath: emptyFile.path,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'uploadAvatar: Formats path correctly and uploads with MIME',
      () async {
        final avatarFile = File('${tempDir.path}/profile_avatar.png');
        await avatarFile.writeAsBytes([1, 2, 3, 4, 5]);

        String? interceptedUrl;
        String? interceptedMethod;

        final mockHttp = MockClient((request) async {
          interceptedUrl = request.url.toString();
          interceptedMethod = request.method;

          if (request.url.path.contains(
            '/storage/v1/object/avatars/user-123/',
          )) {
            return http.Response(
              jsonEncode({'Key': request.url.path}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found: ${request.url.path}', 404);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final storage = SupabaseStorageService(client);

        final result = await storage.uploadAvatar(
          ownerType: 'user',
          ownerId: 'user-123',
          filePath: avatarFile.path,
        );

        expect(result.bucket, equals('avatars'));
        expect(result.path, startsWith('user-123/avatar_'));
        expect(result.path, endsWith('.png'));
        expect(result.fileSizeBytes, equals(5));
        expect(
          result.publicUrl,
          contains('/storage/v1/object/public/avatars/user-123/avatar_'),
        );
        expect(interceptedMethod, equals('POST'));
        expect(
          interceptedUrl,
          contains('/storage/v1/object/avatars/user-123/avatar_'),
        );
      },
    );

    test('uploadChatAttachment: Rejects non-existent attachment', () async {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final storage = SupabaseStorageService(mockClient);

      expect(
        () => storage.uploadChatAttachment(
          chatId: 'chat-uuid-456',
          messageId: 'msg-uuid-789',
          filePath: '${tempDir.path}/missing_doc.pdf',
          mediaKind: 'document',
        ),
        throwsA(isA<FileNotFoundException>()),
      );
    });

    test(
      'uploadChatAttachment: Stores in private attachments bucket with chatId prefix',
      () async {
        final docFile = File('${tempDir.path}/sample_invoice.pdf');
        await docFile.writeAsBytes([37, 80, 68, 70]); // %PDF

        String? interceptedPath;

        final mockHttp = MockClient((request) async {
          interceptedPath = request.url.path;

          if (request.url.path.contains(
            '/storage/v1/object/attachments/chat-uuid-456/msg-uuid-789_sample_invoice.pdf',
          )) {
            return http.Response(
              jsonEncode({'Key': request.url.path}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final storage = SupabaseStorageService(client);

        final result = await storage.uploadChatAttachment(
          chatId: 'chat-uuid-456',
          messageId: 'msg-uuid-789',
          filePath: docFile.path,
          mediaKind: 'document',
        );

        expect(result.bucket, equals('attachments'));
        expect(
          result.path,
          equals('chat-uuid-456/msg-uuid-789_sample_invoice.pdf'),
        );
        expect(result.fileSizeBytes, equals(4));
        // Private attachment references canonical object path rather than permanent public URL
        expect(
          result.publicUrl,
          equals('chat-uuid-456/msg-uuid-789_sample_invoice.pdf'),
        );
        expect(
          interceptedPath,
          contains(
            '/storage/v1/object/attachments/chat-uuid-456/msg-uuid-789_sample_invoice.pdf',
          ),
        );
      },
    );

    test(
      'getAuthorizedUrl: Generates signed URL for private attachments',
      () async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains(
            '/storage/v1/object/sign/attachments/chat-1/msg-1.pdf',
          )) {
            return http.Response(
              jsonEncode({
                'signedURL':
                    '/storage/v1/object/sign/attachments/chat-1/msg-1.pdf?token=secret-token-123',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final storage = SupabaseStorageService(client);

        final signedUrl = await storage.getAuthorizedUrl(
          bucket: 'attachments',
          path: 'chat-1/msg-1.pdf',
          expiresIn: const Duration(hours: 2),
        );

        expect(signedUrl, contains('secret-token-123'));
      },
    );

    test('deleteFile: Deletes file from bucket', () async {
      String? interceptedBody;

      final mockHttp = MockClient((request) async {
        if (request.method == 'DELETE' &&
            request.url.path.contains('/storage/v1/object/attachments')) {
          interceptedBody = request.body;
          return http.Response(
            jsonEncode([
              {'name': 'chat-1/msg-1.pdf'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final storage = SupabaseStorageService(client);

      await storage.deleteFile(bucket: 'attachments', path: 'chat-1/msg-1.pdf');

      expect(interceptedBody, contains('chat-1/msg-1.pdf'));
    });
  });

  group('UploadOrchestrator Resilient Abstraction Tests', () {
    test('uploadAvatar: Returns public URL on immediate success', () async {
      final avatarFile = File('${tempDir.path}/direct_avatar.jpg');
      await avatarFile.writeAsBytes([255, 216, 255]); // JPEG magic bytes

      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({'Key': request.url.path}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final storage = SupabaseStorageService(client);
      final fakeOutbox = _FakeOutboxService();

      final orchestrator = UploadOrchestrator(
        storage: storage,
        outbox: fakeOutbox,
      );

      final url = await orchestrator.uploadAvatar(
        ownerType: 'user',
        ownerId: 'user-888',
        filePath: avatarFile.path,
      );

      expect(
        url,
        contains('/storage/v1/object/public/avatars/user-888/avatar_'),
      );
      expect(fakeOutbox.lastEnqueuedOwnerId, isNull); // Outbox was not needed
    });

    test(
      'uploadAvatar: Enqueues outbox background retry when foreground upload fails',
      () async {
        final avatarFile = File('${tempDir.path}/failing_avatar.jpg');
        await avatarFile.writeAsBytes([255, 216, 255]);

        final mockHttp = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final storage = SupabaseStorageService(client);
        final fakeOutbox = _FakeOutboxService();

        final orchestrator = UploadOrchestrator(
          storage: storage,
          outbox: fakeOutbox,
        );

        await expectLater(
          () => orchestrator.uploadAvatar(
            ownerType: 'user',
            ownerId: 'user-999',
            filePath: avatarFile.path,
          ),
          throwsA(isA<StorageException>()),
        );

        // Verify that outbox fallback was invoked with the exact parameters
        expect(fakeOutbox.lastEnqueuedOwnerType, equals('user'));
        expect(fakeOutbox.lastEnqueuedOwnerId, equals('user-999'));
        expect(fakeOutbox.lastEnqueuedFilePath, equals(avatarFile.path));
      },
    );
  });
}
