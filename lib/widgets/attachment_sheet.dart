import 'package:flutter/material.dart';
import 'package:instant_messenger/controller/chat_screen_controller.dart';
import 'package:instant_messenger/services/bottom_sheet_service.dart';
import 'package:instant_messenger/widgets/gallery_picker_sheet.dart';

class AttachmentSheet extends StatelessWidget {
  final ChatScreenController controller;

  const AttachmentSheet({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(
              context,
              icon: Icons.camera_alt,
              label: 'Camera',
              color: Colors.pink,
              onTap: controller.pickFromCamera,
            ),
_item(
  context,
  icon: Icons.photo,
  label: 'Gallery',
  color: Colors.purple,
 onTap: () {
  Navigator.pop(context); // close attachment sheet (local)

  BottomSheetService.show(
    context: context,
    child: GalleryPickerSheet(
      onSend: (files, caption) {
        controller.sendImages(files, caption);
      },
    ),
  );
},
),


            _item(
              context,
              icon: Icons.audiotrack,
              label: 'Audio',
              color: Colors.orange,
              onTap: controller.pickAudio,
            ),
            _item(
              context,
              icon: Icons.insert_drive_file,
              label: 'Document',
              color: Colors.blue,
              onTap: controller.pickDocument,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
