import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoThumbnailService {
  static Future<File?> generate(String videoPath) async {
    final dir = await getTemporaryDirectory();

    final thumbPath = await VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: dir.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 75,
    );

    if (thumbPath == null) return null;
    return File(thumbPath);
  }
}
