import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class MediaCompressService {
  /// 🖼 IMAGE — ~80% quality using native platform image compressor
  static Future<File> compressImage(File file) async {
    debugPrint('[Compress] image ${file.path}');
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/compressed_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 80,
        keepExif: true,
      );

      if (compressed != null && await File(compressed.path).exists()) {
        return File(compressed.path);
      }
      return file;
    } catch (e) {
      debugPrint('[Compress] image failed ($e) → using original');
      return file;
    }
  }

  /// 🎞 VIDEO — medium (~80–85% perceived quality) using native Android MediaCodec / iOS AVFoundation
  static Future<File> compressVideo(File file) async {
    debugPrint('[Compress] video ${file.path}');
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (info != null && info.file != null && await info.file!.exists()) {
        return info.file!;
      }
      return file;
    } catch (e) {
      debugPrint('[Compress] video failed ($e) → using original');
      return file;
    }
  }

  /// 🎙 AUDIO — passthrough validation for audio/voice files (no heavy FFmpeg required)
  static Future<File> compressAudio(File file) async {
    debugPrint('[Compress] audio ${file.path}');
    try {
      if (await file.exists()) {
        return file;
      }
      return file;
    } catch (e) {
      debugPrint('[Compress] audio failed ($e) → using original');
      return file;
    }
  }
}
