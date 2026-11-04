import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/features/media/presentation/controllers/chat_media_controller.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';

class AttachmentSheet extends ConsumerWidget {
  final ChatControllerArgs args;
  final String otherName;
  final String? otherAvatar;
  final ChatMediaController mediaPicker;
  final ChatSendNotifier? sendNotifier;

  AttachmentSheet({
    super.key,
    required this.args,
    required this.otherName,
    this.otherAvatar,
    ChatMediaController? mediaPicker,
    this.sendNotifier,
  }) : mediaPicker = mediaPicker ?? ChatMediaController();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
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
                onTap: () async {
                  await mediaPicker.pickFromCamera();
                },
              ),
              _item(
                context,
                icon: Icons.photo,
                label: 'Gallery',
                color: Colors.purple,
                onTap: () async {
                  // Safely capture the notifier while mounted before the async gap
                  final ChatSendNotifier notifier = sendNotifier ??
                      ref.read(chatSendNotifierProvider(args).notifier);
                  final files = await mediaPicker.pickFromGallery();
                  if (files.isNotEmpty) {
                    await notifier.sendImages(
                      files,
                      '',
                      otherName: otherName,
                      otherAvatar: otherAvatar,
                    );
                  }
                },
              ),
              _item(
                context,
                icon: Icons.audiotrack,
                label: 'Audio',
                color: Colors.orange,
                onTap: () async {
                  // Safely capture the notifier while mounted before the async gap
                  final ChatSendNotifier notifier = sendNotifier ??
                      ref.read(chatSendNotifierProvider(args).notifier);
                  final file = await mediaPicker.pickAudio();
                  if (file != null) {
                    await notifier.sendAudio(
                      file,
                      otherName: otherName,
                      otherAvatar: otherAvatar,
                    );
                  }
                },
              ),
              _item(
                context,
                icon: Icons.insert_drive_file,
                label: 'Document',
                color: Colors.blue,
                onTap: () async {
                  // Safely capture the notifier while mounted before the async gap
                  final ChatSendNotifier notifier = sendNotifier ??
                      ref.read(chatSendNotifierProvider(args).notifier);
                  final file = await mediaPicker.pickDocument();
                  if (file != null) {
                    await notifier.sendDocument(
                      file,
                      otherName: otherName,
                      otherAvatar: otherAvatar,
                    );
                  }
                },
              ),
            ],
          ),
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
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
