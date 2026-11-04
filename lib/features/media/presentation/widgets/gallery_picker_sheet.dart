import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/media/presentation/providers/media_providers.dart';
import 'package:instant_messenger/shared/utils/bottom_sheet_service.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:cross_file/cross_file.dart';

class GalleryPickerSheet extends StatelessWidget {
  final void Function(List<XFile>, String caption) onSend;
  final DraggableScrollableController sheetController =
      DraggableScrollableController();

  GalleryPickerSheet({super.key, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        BottomSheetService.close(context);
      },
      child: DraggableScrollableSheet(
        controller: sheetController,
        shouldCloseOnMinExtent: true,
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.45,
        maxChildSize: 0.90,
        snap: true,
        snapSizes: const [0.55, 0.90],
        builder: (context, scrollController) {
          return Consumer(
            builder: (context, ref, _) {
              final c = ref.watch(galleryPickerControllerProvider);
              final notifier = ref.read(
                galleryPickerControllerProvider.notifier,
              );
              final canSend = c.selectedIndexes.isNotEmpty;

              final cs = Theme.of(context).colorScheme;

              return Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 8),

                        // 🔹 Drag handle
                        const SizedBox(height: 8),

                        // 🔹 Drag handle (FIXED – manually drives the sheet)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            final delta = details.primaryDelta ?? 0;

                            final newSize =
                                sheetController.size -
                                delta / MediaQuery.of(context).size.height;

                            sheetController.jumpTo(newSize.clamp(0.45, 0.90));
                          },
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        const SizedBox(height: 8),

                        // 🔹 Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                'Gallery',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.hd_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // 🔹 GRID (IMPORTANT CHANGE)
                        Expanded(
                          child: c.loading
                              ? const Center(child: CircularProgressIndicator())
                              : GridView.builder(
                                  controller: scrollController, // 🔥 KEY
                                  padding: const EdgeInsets.all(4),
                                  primary: false,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 4,
                                        crossAxisSpacing: 4,
                                        mainAxisSpacing: 4,
                                      ),
                                  itemCount: c.items.length,
                                  itemBuilder: (_, i) {
                                    final selected = c.isSelected(i);
                                    final isVideo = c.isVideo(i);
                                    final entity = c.entityAt(i);

                                    return GestureDetector(
                                      onTap: () => notifier.toggle(i),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          AssetEntityImage(
                                            entity,
                                            fit: BoxFit.cover,
                                          ),

                                          if (isVideo)
                                            const Positioned(
                                              bottom: 6,
                                              right: 6,
                                              child: Icon(
                                                Icons.videocam,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),

                                          if (selected)
                                            Container(
                                              color: Colors.black.withValues(
                                                alpha: 0.35,
                                              ),
                                            ),

                                          if (selected)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: CircleAvatar(
                                                radius: 12,
                                                backgroundColor: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                child: Text(
                                                  '${c.selectedIndexes.toList().indexOf(i) + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),

                    // 🔹 FLOATING CAPTION BAR (keyboard aware)
                    if (canSend)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                        child: _CaptionBar(
                          captionController: notifier.captionController,
                          selectedFiles: c.selectedFiles,
                          selectedCount: c.selectedIndexes.length,
                          onSend: onSend,
                          sheetController: sheetController,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CaptionBar extends StatelessWidget {
  final TextEditingController captionController;
  final List<XFile> selectedFiles;
  final int selectedCount;
  final void Function(List<XFile>, String) onSend;
  final DraggableScrollableController sheetController;

  const _CaptionBar({
    required this.captionController,
    required this.selectedFiles,
    required this.selectedCount,
    required this.onSend,
    required this.sheetController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final captionBg = isDark ? cs.surfaceContainerHigh : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: captionBg,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              controller: captionController,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: 'Add a caption...',
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFFA9B8BF) : cs.onSurfaceVariant,
                  fontSize: 16,
                ),
                border: InputBorder.none,
              ),
              onTap: () {
                sheetController.animateTo(
                  0.90, // 👈 expand sheet
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
              },
            ),
          ),
          GestureDetector(
            onTap: () {
              onSend(selectedFiles, captionController.text.trim());
              BottomSheetService.close(context);
            },
            child: CircleAvatar(
              radius: 22,
              backgroundColor: cs.primary,
              child: Text(
                '$selectedCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
