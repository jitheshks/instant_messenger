import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/storage/local_file_storage.dart';

void main() {
  group('LocalFileStorage Unit Tests', () {
    late Directory tempDir;
    late LocalFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('local_storage_test_');
      storage = LocalFileStorage(baseDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'saveFile writes bytes and getFile retrieves persisted file',
      () async {
        final sampleBytes = utf8.encode('Hello Offline Messenger');
        final file = await storage.saveFile(
          subDir: 'attachments',
          fileName: 'note.txt',
          bytes: sampleBytes,
        );

        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), 'Hello Offline Messenger');

        final retrieved = await storage.getFile(
          subDir: 'attachments',
          fileName: 'note.txt',
        );
        expect(retrieved, isNotNull);
        expect(await retrieved!.readAsString(), 'Hello Offline Messenger');
      },
    );

    test('computeSha256 produces exact cryptographic hex digest', () {
      final input = utf8.encode('test-data-for-sha256');
      final hash = storage.computeSha256(input);
      expect(
        hash,
        '534d74989d698e739449ecf36e3500b7d34e472c021a344218400eeb710cc8ca',
      );
    });

    test(
      'blocks path traversal attacks attempting to escape sandbox',
      () async {
        final maliciousBytes = utf8.encode('malicious content');

        // Attempt traversal via subDir
        expect(
          () => storage.saveFile(
            subDir: '../../outside',
            fileName: 'exploit.txt',
            bytes: maliciousBytes,
          ),
          throwsA(isA<PathTraversalException>()),
        );

        // Attempt traversal via fileName
        expect(
          () => storage.saveFile(
            subDir: 'safe_sub',
            fileName: '../../escape.txt',
            bytes: maliciousBytes,
          ),
          throwsA(isA<PathTraversalException>()),
        );
      },
    );

    test('enforces storage quota and rejects writes that exceed limit', () async {
      final smallBytes = List<int>.filled(500, 1);
      final hugeBytes = List<int>.filled(1000, 2);

      // Save initial 500 bytes with 1000 byte quota (allowed)
      await storage.saveFile(
        subDir: 'media',
        fileName: 'file1.bin',
        bytes: smallBytes,
        maxQuotaBytes: 1000,
      );

      // Attempt saving 1000 more bytes (500 + 1000 = 1500 > 1000 quota -> rejects)
      expect(
        () => storage.saveFile(
          subDir: 'media',
          fileName: 'file2.bin',
          bytes: hugeBytes,
          maxQuotaBytes: 1000,
        ),
        throwsA(isA<StorageQuotaExceededException>()),
      );
    });

    test(
      'getDirectorySizeBytes and getTotalStorageSizeBytes calculate accurate sizes',
      () async {
        final data1 = List<int>.filled(256, 1);
        final data2 = List<int>.filled(512, 2);

        await storage.saveFile(
          subDir: 'audios',
          fileName: 'voice1.m4a',
          bytes: data1,
        );
        await storage.saveFile(
          subDir: 'audios',
          fileName: 'voice2.m4a',
          bytes: data2,
        );
        await storage.saveFile(
          subDir: 'avatars',
          fileName: 'user.png',
          bytes: data1,
        );

        final audioSize = await storage.getDirectorySizeBytes('audios');
        final avatarSize = await storage.getDirectorySizeBytes('avatars');
        final totalSize = await storage.getTotalStorageSizeBytes();

        expect(audioSize, 768);
        expect(avatarSize, 256);
        expect(totalSize, 1024);
      },
    );

    test('deleteFile and clearDirectory successfully remove files', () async {
      await storage.saveFile(
        subDir: 'temp',
        fileName: 'temp1.tmp',
        bytes: [1, 2, 3],
      );
      await storage.saveFile(
        subDir: 'temp',
        fileName: 'temp2.tmp',
        bytes: [4, 5, 6],
      );

      final deleted = await storage.deleteFile(
        subDir: 'temp',
        fileName: 'temp1.tmp',
      );
      expect(deleted, isTrue);

      final exists = await storage.getFile(
        subDir: 'temp',
        fileName: 'temp1.tmp',
      );
      expect(exists, isNull);

      await storage.clearDirectory('temp');
      final remaining = await storage.getDirectorySizeBytes('temp');
      expect(remaining, 0);
    });
  });
}
