import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/media/data/video_thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoThumbnailService Unit Tests', () {
    test(
      'generate returns null gracefully when input video path is non-existent',
      () async {
        final result = await VideoThumbnailService.generate(
          '/non/existent/video/path.mp4',
        );
        expect(result, isNull);
      },
    );
  });
}
