import 'package:instant_messenger/services/outbox_service.dart';
import 'package:instant_messenger/services/uploads/cloudinary_foreground_service.dart';

class UploadOrchestrator {
  final CloudinaryForegroundService foreground;
  final OutboxService outbox;

  UploadOrchestrator({
    required this.foreground,
    required this.outbox,
  });

  Future<String> uploadAvatar({
    required String ownerType,
    required String ownerId,
    required String filePath,
  }) async {
    final folder = ownerType == 'user'
        ? 'instant_messenger/avatars/users/$ownerId'
        : 'instant_messenger/avatars/groups/$ownerId';

    try {
      final result = await foreground.upload(
        filePath: filePath,
        folder: folder,
        resourceType: 'image',
      );

      return result['secure_url'];
    } catch (_) {
      await outbox.enqueueAvatarUpload(
        ownerType: ownerType,
        ownerId: ownerId,
        filePath: filePath,
      );
      rethrow;
    }
  }
}
