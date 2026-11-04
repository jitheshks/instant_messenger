import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/media/data/media_compress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaCompressService Unit & Fallback Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_compress_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'compressImage safely falls back to original file if non-existent or error occurs',
      () async {
        final nonExistent = File('${tempDir.path}/non_existent.jpg');
        final result = await MediaCompressService.compressImage(nonExistent);

        expect(result.path, equals(nonExistent.path));
      },
    );

    test(
      'compressVideo safely falls back to original file if non-existent or error occurs',
      () async {
        final nonExistent = File('${tempDir.path}/non_existent.mp4');
        final result = await MediaCompressService.compressVideo(nonExistent);

        expect(result.path, equals(nonExistent.path));
      },
    );

    test(
      'compressAudio safely falls back to original file if non-existent or error occurs',
      () async {
        final nonExistent = File('${tempDir.path}/non_existent.m4a');
        final result = await MediaCompressService.compressAudio(nonExistent);

        expect(result.path, equals(nonExistent.path));
      },
    );

    test(
      'compressAudio returns existing file intact on valid audio input',
      () async {
        final sampleAudio = File('${tempDir.path}/sample_voice.m4a');
        await sampleAudio.writeAsString('mock audio binary data stream');

        final result = await MediaCompressService.compressAudio(sampleAudio);
        expect(result.path, equals(sampleAudio.path));
        expect(await result.exists(), isTrue);
      },
    );

    test(
      'compressImage with empty/corrupt image returns original file without throwing unhandled exception',
      () async {
        final corruptImg = File('${tempDir.path}/corrupt.png');
        await corruptImg.writeAsString('not a real image payload');

        final result = await MediaCompressService.compressImage(corruptImg);
        expect(result.existsSync(), isTrue);
      },
    );
  });
}
