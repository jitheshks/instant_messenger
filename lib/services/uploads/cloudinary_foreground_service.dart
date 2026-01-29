import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:instant_messenger/services/uploads/cloudinary_request_builder.dart';

class CloudinaryForegroundService {
  final String cloudName;
  final String uploadPreset;

  CloudinaryForegroundService({
    required this.cloudName,
    required this.uploadPreset,
  });

Future<Map<String, dynamic>> upload({
  required String filePath,
  required String folder,
  required String resourceType,
}) async {
  debugPrint('[Cloudinary] upload() called');
  debugPrint('[Cloudinary] filePath=$filePath');

  final file = File(filePath);
  final exists = await file.exists();
  final size = exists ? await file.length() : 0;

  debugPrint('[Cloudinary] file exists=$exists size=$size');

  if (!exists || size == 0) {
    throw Exception('File does not exist or is empty: $filePath');
  }

  final uri = CloudinaryRequestBuilder.uploadUri(
    cloudName,
    resourceType,
  );

  debugPrint('[Cloudinary] uri=$uri');
  debugPrint('[Cloudinary] preset=$uploadPreset folder=$folder');

  final request = await CloudinaryRequestBuilder.multipart(
    uri: uri,
    preset: uploadPreset,
    folder: folder,
    filePath: filePath,
  );

  // 👇 THIS PART IS THE IMPORTANT FIX
  try {
    debugPrint('[Cloudinary] sending request...');

    final response = await request.send();
    final body = await response.stream.bytesToString();

    debugPrint('[Cloudinary] STATUS=${response.statusCode}');
    debugPrint('[Cloudinary] BODY=$body');

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Cloudinary error: $body');
    }

    return jsonDecode(body);
  } catch (e, st) {
    debugPrint('[Cloudinary] ❌ ERROR=$e');
    debugPrintStack(stackTrace: st);
    rethrow;
  }
}


}
