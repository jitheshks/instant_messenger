import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

@immutable
class GalleryPickerState {
  final bool loading;
  final List<AssetEntity> entities;
  final List<XFile> items;
  final Set<int> selectedIndexes;

  const GalleryPickerState({
    this.loading = true,
    this.entities = const [],
    this.items = const [],
    this.selectedIndexes = const {},
  });

  List<XFile> get selectedFiles =>
      selectedIndexes.map((i) => items[i]).toList();

  bool isSelected(int index) => selectedIndexes.contains(index);
  bool isVideo(int index) => entities[index].type == AssetType.video;
  AssetEntity entityAt(int index) => entities[index];

  GalleryPickerState copyWith({
    bool? loading,
    List<AssetEntity>? entities,
    List<XFile>? items,
    Set<int>? selectedIndexes,
  }) {
    return GalleryPickerState(
      loading: loading ?? this.loading,
      entities: entities ?? this.entities,
      items: items ?? this.items,
      selectedIndexes: selectedIndexes ?? this.selectedIndexes,
    );
  }
}

class GalleryPickerNotifier extends Notifier<GalleryPickerState> {
  final TextEditingController captionController = TextEditingController();

  @override
  GalleryPickerState build() {
    ref.onDispose(captionController.dispose);
    Future.microtask(() => load());
    return const GalleryPickerState();
  }

  bool get loading => state.loading;
  List<XFile> get items => state.items;
  Set<int> get selectedIndexes => state.selectedIndexes;
  List<XFile> get selectedFiles => state.selectedFiles;
  bool isSelected(int index) => state.isSelected(index);
  bool isVideo(int index) => state.isVideo(index);
  AssetEntity entityAt(int index) => state.entityAt(index);

  Future<void> load() async {
    state = state.copyWith(loading: true);

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      state = state.copyWith(loading: false);
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      state = state.copyWith(loading: false);
      return;
    }

    final recent = albums.first;
    final media = await recent.getAssetListPaged(page: 0, size: 200);

    final loadedItems = <XFile>[];
    for (final asset in media) {
      final file = await asset.file;
      if (file != null) {
        loadedItems.add(XFile(file.path));
      }
    }

    state = GalleryPickerState(
      loading: false,
      entities: List.unmodifiable(media),
      items: List.unmodifiable(loadedItems),
      selectedIndexes: const {},
    );
  }

  void toggle(int index) {
    final next = Set<int>.from(state.selectedIndexes);
    if (!next.remove(index)) {
      next.add(index);
    }
    state = state.copyWith(selectedIndexes: Set.unmodifiable(next));
  }

  void clearSelection() {
    state = state.copyWith(selectedIndexes: const {});
  }
}
