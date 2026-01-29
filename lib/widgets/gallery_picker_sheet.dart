import 'package:flutter/material.dart';
import 'package:instant_messenger/services/bottom_sheet_service.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:instant_messenger/controller/gallery_picker_controller.dart';

class GalleryPickerSheet extends StatelessWidget {
  final void Function(List<XFile>, String caption) onSend;
  final DraggableScrollableController sheetController =
    DraggableScrollableController();


   GalleryPickerSheet({
    super.key,
    required this.onSend,
  });

@override
Widget build(BuildContext context) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
    BottomSheetService.close(context);      },
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
        return ChangeNotifierProvider(
          create: (_) => GalleryPickerController()..load(),
          child: Consumer<GalleryPickerController>(
            builder: (context, c, _) {
              final canSend = c.selectedIndexes.isNotEmpty;

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
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

    sheetController.jumpTo(
      newSize.clamp(0.45, 0.90),
    );
  },
  child: Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  ),
),

const SizedBox(height: 8),

                        const SizedBox(height: 8),

                        // 🔹 Header
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                'Gallery',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Spacer(),
                              Icon(Icons.hd_outlined),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // 🔹 GRID (IMPORTANT CHANGE)
                        Expanded(
                          child: c.loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
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
                                      onTap: () => c.toggle(i),
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
                                              color: Colors.black
                                                  .withOpacity(0.35),
                                            ),

                                          if (selected)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: CircleAvatar(
                                                radius: 12,
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .primaryColor,
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
                        bottom:
                            MediaQuery.of(context).viewInsets.bottom + 8,
                        child: _CaptionBar(
                          controller: c,
                          onSend: onSend,
                          sheetController : sheetController
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

}


class _CaptionBar extends StatelessWidget {
  final GalleryPickerController controller;
  final void Function(List<XFile>, String) onSend;
    final DraggableScrollableController sheetController; 


   const _CaptionBar({
    required this.controller,
    required this.onSend,
        required this.sheetController, 
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black26,
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              controller: controller.captionController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add a caption...',
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
              onSend(
                controller.selectedFiles,
                controller.captionController.text.trim(),
              );
  BottomSheetService.close(context);    
             },
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                '${controller.selectedIndexes.length}',
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
