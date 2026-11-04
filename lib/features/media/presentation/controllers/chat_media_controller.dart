import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// UI-only media picker (WhatsApp / Telegram style)
class ChatMediaController {
  final Future<List<XFile>> Function()? _galleryPicker;
  final Future<XFile?> Function()? _documentPicker;
  final Future<XFile?> Function()? _audioPicker;
  final Future<File?> Function()? _cameraPicker;

  ChatMediaController({
    Future<List<XFile>> Function()? galleryPicker,
    Future<XFile?> Function()? documentPicker,
    Future<XFile?> Function()? audioPicker,
    Future<File?> Function()? cameraPicker,
  })  : _galleryPicker = galleryPicker,
        _documentPicker = documentPicker,
        _audioPicker = audioPicker,
        _cameraPicker = cameraPicker;

  /// 📸 Pick images or videos from gallery
  /// Returns empty list if user cancels
  Future<List<XFile>> pickFromGallery() async {
    if (_galleryPicker != null) {
      return _galleryPicker();
    }
    final result = await FilePicker.pickFiles(
      type: FileType.media,
    );

    if (result.isEmpty) {
      return [];
    }

    return result
        .where((f) => f.path != null)
        .map((f) => XFile(f.path!))
        .toList();
  }

  /// 📄 Pick a document (PDF, ZIP, APK, etc.)
  /// Returns null if user cancels
  Future<XFile?> pickDocument() async {
    if (_documentPicker != null) {
      return _documentPicker();
    }
    final file = await FilePicker.pickFile(
      type: FileType.any,
    );

    if (file == null || file.path == null) return null;

    return XFile(file.path!, name: file.name);
  }

  /// 🎵 Pick an audio file
  /// Returns null if user cancels
  Future<XFile?> pickAudio() async {
    if (_audioPicker != null) {
      return _audioPicker();
    }
    final file = await FilePicker.pickFile(
      type: FileType.audio,
    );

    if (file == null || file.path == null) return null;

    return XFile(file.path!);
  }

  /// 📷 Camera placeholder
  Future<File?> pickFromCamera() async {
    if (_cameraPicker != null) {
      return _cameraPicker();
    }
    return null;
  }
}
