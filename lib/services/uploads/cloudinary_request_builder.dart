import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class CloudinaryRequestBuilder {
  static Uri uploadUri(String cloudName, String resourceType) {
    return Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload',
    );
  }

  static Future<http.MultipartRequest> multipart({
    required Uri uri,
    required String preset,
    required String folder,
    required String filePath,
  }) async {
    // ───────────────── DEBUG LOGS ─────────────────
    debugPrint('[Cloudinary] building multipart request');
    debugPrint('[Cloudinary] uri=$uri');
    debugPrint('[Cloudinary] preset=$preset');
    debugPrint('[Cloudinary] folder=$folder');
    debugPrint('[Cloudinary] filePath=$filePath');

    final file = File(filePath);
    final exists = file.existsSync();
    final size = exists ? file.lengthSync() : 0;

    debugPrint('[Cloudinary] file exists=$exists size=$size');

    if (!exists) {
      throw Exception('[Cloudinary] File does not exist at $filePath');
    }

    // ───────────────── REQUEST BUILD ─────────────────
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = preset
      ..fields['folder'] = folder;

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      filePath,
    );

    request.files.add(multipartFile);

    // ───────────────── MORE DEBUG ─────────────────
    debugPrint('[Cloudinary] fields=${request.fields}');
    debugPrint('[Cloudinary] filename=${multipartFile.filename}');
    debugPrint('[Cloudinary] contentType=${multipartFile.contentType}');
    debugPrint('[Cloudinary] headers=${request.headers}');

    return request;
  }
}
