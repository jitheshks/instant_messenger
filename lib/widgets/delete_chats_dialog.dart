import 'package:flutter/material.dart';

Future<bool?> showDeleteChatDialog(BuildContext context, int selectedCount) {
  bool deleteMedia = false;

  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            selectedCount == 1
                ? 'Delete this chat?'
                : 'Delete $selectedCount chats?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: deleteMedia,
                onChanged: (v) => setState(() => deleteMedia = v ?? false),
                title: Text(
                  selectedCount == 1
                      ? "Also delete media received in this chat from the device gallery"
                      : "Also delete media received in these chats from the device gallery",
                  style: const TextStyle(fontSize: 14),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, deleteMedia),
              child: Text(
                selectedCount == 1 ? 'Delete chat' : 'Delete chats',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    },
  );
}
