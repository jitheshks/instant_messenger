import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter/material.dart';

enum ChatFileKind { image, video, audio, document, unknown }

class PickedChatFile {
  final XFile file;
  final ChatFileKind kind;
  final String? mime; // keep for future, but will be null for now
  PickedChatFile({required this.file, required this.kind, this.mime});
}

class FilePickerService {
  // Generic attachments for chats
  static Future<List<PickedChatFile>> pickImages({
    bool allowMultiple = true,
  }) async {
    final List<PlatformFile> res;
    if (allowMultiple) {
      res = await FilePicker.pickFiles(type: FileType.image);
    } else {
      final single = await FilePicker.pickFile(type: FileType.image);
      res = single != null ? [single] : [];
    }
    return _mapResult(res, ChatFileKind.image);
  }

  static Future<List<PickedChatFile>> pickVideos({
    bool allowMultiple = true,
  }) async {
    final List<PlatformFile> res;
    if (allowMultiple) {
      res = await FilePicker.pickFiles(type: FileType.video);
    } else {
      final single = await FilePicker.pickFile(type: FileType.video);
      res = single != null ? [single] : [];
    }
    return _mapResult(res, ChatFileKind.video);
  }

  static Future<List<PickedChatFile>> pickDocuments({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
  }) async {
    final exts = allowedExtensions ??
        ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
    final List<PlatformFile> res;
    if (allowMultiple) {
      res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: exts,
      );
    } else {
      final single = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: exts,
      );
      res = single != null ? [single] : [];
    }
    return _mapResult(res, ChatFileKind.document);
  }

  static Future<List<PickedChatFile>> pickAny({
    bool allowMultiple = true,
  }) async {
    final List<PlatformFile> res;
    if (allowMultiple) {
      res = await FilePicker.pickFiles(type: FileType.any);
    } else {
      final single = await FilePicker.pickFile(type: FileType.any);
      res = single != null ? [single] : [];
    }
    return _mapAny(res);
  }

  // Avatar convenience: pick one image and crop to square

  static Future<XFile?> pickAndCropAvatar(
    BuildContext context, {
    int quality = 90,
  }) async {
    debugPrint('[AvatarPicker] STEP 1: opening FilePicker');

    final single = await FilePicker.pickFile(type: FileType.image);

    if (single == null || single.path == null) {
      debugPrint('[AvatarPicker] CANCELLED: picker result is null/empty');
      return null;
    }

    final path = single.path;
    debugPrint('[AvatarPicker] STEP 2: picked path = $path');

    if (path == null) {
      debugPrint('[AvatarPicker] ERROR: picked path is null');
      return null;
    }

    debugPrint('[AvatarPicker] STEP 3: launching cropper');

    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: quality,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop',
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.square,
          showCropGrid: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop',
          aspectRatioLockEnabled: true,
          rotateButtonsHidden: false,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    debugPrint('[AvatarPicker] STEP 4: cropper returned = $cropped');

    if (cropped == null) {
      debugPrint('[AvatarPicker] CANCELLED: user closed cropper');
      return null;
    }

    final croppedPath = cropped.path;
    debugPrint('[AvatarPicker] STEP 5: cropped path = $croppedPath');

    final exists = File(croppedPath).existsSync();
    debugPrint('[AvatarPicker] STEP 6: cropped file exists = $exists');

    if (!exists) {
      debugPrint('[AvatarPicker] ❌ FATAL: cropped file does NOT exist on disk');
      return null;
    }

    final name = croppedPath.split(Platform.pathSeparator).last;
    debugPrint('[AvatarPicker] STEP 7: returning XFile name=$name');

    return XFile(croppedPath, name: name);
  }

  // Helpers
  static List<PickedChatFile> _mapResult(
    List<PlatformFile> res,
    ChatFileKind kind,
  ) {
    if (res.isEmpty) return const [];
    return res
        .where((f) => f.path != null)
        .map((f) {
          final xf = f.xFile; // always non-null when path is present
          return PickedChatFile(file: xf, kind: kind, mime: null);
        })
        .toList(growable: false);
  }

  static ChatFileKind _inferKind(String? ext) {
    final e = (ext ?? '').toLowerCase();
    const img = {'jpg', 'jpeg', 'png', 'webp', 'heic'};
    const vid = {'mp4', 'mov', 'mkv', 'webm', 'avi'};
    const aud = {'mp3', 'aac', 'wav', 'flac', 'ogg', 'm4a'};
    const doc = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'};
    if (img.contains(e)) return ChatFileKind.image;
    if (vid.contains(e)) return ChatFileKind.video;
    if (aud.contains(e)) return ChatFileKind.audio;
    if (doc.contains(e)) return ChatFileKind.document;
    return ChatFileKind.unknown;
  }

  static List<PickedChatFile> _mapAny(List<PlatformFile> res) {
    if (res.isEmpty) return const [];
    return res
        .where((f) => f.path != null)
        .map((f) {
          final kind = _inferKind(f.extension);
          final xf = f.xFile;
          return PickedChatFile(file: xf, kind: kind, mime: null);
        })
        .toList(growable: false);
  }
}
