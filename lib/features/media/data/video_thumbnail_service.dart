import 'dart:io';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

class VideoThumbnailService {
  static final _plugin = FcNativeVideoThumbnail();

  static Future<File?> generate(String videoPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final thumbPath =
          '${dir.path}/thumb_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final success = await _plugin.saveThumbnailToFile(
        srcFile: videoPath,
        destFile: thumbPath,
        width: 480,
        height: 480,
        format: 'jpeg',
        quality: 75,
      );

      if (success && await File(thumbPath).exists()) {
        return File(thumbPath);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
