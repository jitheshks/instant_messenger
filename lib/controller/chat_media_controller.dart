// lib/controller/chat_media_controller.dart

import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// UI-only media picker (WhatsApp / Telegram style)
/// ❌ No Firestore
/// ❌ No MIME detection
/// ❌ No compression
class ChatMediaController {
  /// 📸 Pick images or videos from gallery
  /// Returns empty list if user cancels
  Future<List<XFile>> pickFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      return [];
    }

    return result.files
        .where((f) => f.path != null)
        .map((f) => XFile(f.path!))
        .toList();
  }

  /// 📄 Pick a document (PDF, ZIP, APK, etc.)
  /// Returns null if user cancels
  Future<XFile?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    if (file.path == null) return null;

    // ❌ Do NOT attach mimeType here
    return XFile(file.path!, name: file.name);
  }

  /// 🎵 Pick an audio file
  /// Returns null if user cancels
  Future<XFile?> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    if (file.path == null) return null;

    return XFile(file.path!);
  }

  /// 📷 Camera placeholder
  /// Implement later using image_picker / camera
  Future<File?> pickFromCamera() async {
    return null;
  }
}
