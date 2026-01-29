import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:cross_file/cross_file.dart';

class GalleryPickerController extends ChangeNotifier {
  bool loading = true;

  // ---------------- INTERNAL STATE ----------------
  final List<AssetEntity> _entities = [];
  final List<XFile> _items = [];
  final Set<int> _selectedIndexes = {};

  // 🔥 Caption controller (Provider-managed)
  final TextEditingController captionController = TextEditingController();

  // ---------------- PUBLIC GETTERS ----------------
  List<XFile> get items => _items;
  Set<int> get selectedIndexes => _selectedIndexes;

  List<XFile> get selectedFiles =>
      _selectedIndexes.map((i) => _items[i]).toList();

  bool isSelected(int index) => _selectedIndexes.contains(index);

  // ---------------- LOAD MEDIA ----------------
  Future<void> load() async {
    loading = true;
    notifyListeners();

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      loading = false;
      notifyListeners();
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // images + videos
      onlyAll: true,
    );

    if (albums.isEmpty) {
      loading = false;
      notifyListeners();
      return;
    }

    final recent = albums.first;

    final media = await recent.getAssetListPaged(
      page: 0,
      size: 200,
    );

    _entities
      ..clear()
      ..addAll(media);

    _items.clear();

    for (final asset in _entities) {
      final file = await asset.file;
      if (file != null) {
        _items.add(XFile(file.path));
      }
    }

    _selectedIndexes.clear();
    loading = false;
    notifyListeners();
  }

  // ---------------- SELECTION ----------------
  void toggle(int index) {
    if (_selectedIndexes.contains(index)) {
      _selectedIndexes.remove(index);
    } else {
      _selectedIndexes.add(index);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIndexes.clear();
    notifyListeners();
  }

  // ---------------- UI HELPERS ----------------
  bool isVideo(int index) => _entities[index].type == AssetType.video;

  AssetEntity entityAt(int index) => _entities[index];

  // ---------------- CLEANUP ----------------
  @override
  void dispose() {
    captionController.dispose(); // ✅ REQUIRED
    super.dispose();
  }
}
