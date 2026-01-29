import 'dart:io';
import 'package:photo_manager/photo_manager.dart';

class GalleryService {
  Future<List<File>> loadRecentImages({int limit = 60}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    final recent = albums.first;
    final assets = await recent.getAssetListRange(
      start: 0,
      end: limit,
    );

    final files = <File>[];
    for (final a in assets) {
      final f = await a.file;
      if (f != null) files.add(f);
    }
    return files;
  }
}
