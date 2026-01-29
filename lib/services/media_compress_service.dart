import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_compress/flutter_media_compress.dart';

class MediaCompressService {
  /// 🖼 IMAGE — ~80% quality
  static Future<File> compressImage(File file) async {
    debugPrint('[Compress] image ${file.path}');

    final result = await FlutterMediaCompress.compressSingle(
      file: file,
      config: const CompressionConfig(
        mediaType: MediaType.image,
        quality: CompressQuality.custom,
        customQuality: 80, // ✅ 80% quality
        keepMetadata: true,
      ),
    );

     if (!result.isSuccess) {
      debugPrint('[Compress] image failed → using original');
      return file;
    }

    return result.compressedFile;
  }

  /// 🎞 VIDEO — medium (~80–85% perceived quality)
  static Future<File> compressVideo(File file) async {
    debugPrint('[Compress] video ${file.path}');

    final result = await FlutterMediaCompress.compressSingle(
      file: file,
      config: const CompressionConfig(
        mediaType: MediaType.video,
        quality: CompressQuality.medium, // ✅ balanced
      ),
    );
 if (!result.isSuccess) {
      debugPrint('[Compress] video failed → using original');
      return file;
    }

    return result.compressedFile;
  }

  /// 🎙 AUDIO — voice messages only (~20% smaller)
  static Future<File> compressAudio(File file) async {
    debugPrint('[Compress] audio ${file.path}');

    final result = await FlutterMediaCompress.compressSingle(
      file: file,
      config: const CompressionConfig(
        mediaType: MediaType.audio,
        quality: CompressQuality.medium, // outputs .m4a
      ),
    );

  
    if (!result.isSuccess) {
      debugPrint('[Compress] audio failed → using original');
      return file;
    }

    return result.compressedFile;
  }
}
