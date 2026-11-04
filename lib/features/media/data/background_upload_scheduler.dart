import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Schedules background uploads via WorkManager
class BackgroundUploadScheduler {
  // ------------------------------------------------------------
  // TASK NAMES
  // ------------------------------------------------------------

  static const String _mediaTask = 'upload_media';
  static const String _avatarTask = 'upload_avatar';

  // ------------------------------------------------------------
  // CHAT MEDIA UPLOAD
  // ------------------------------------------------------------

  /// Enqueue a background chat media upload
  static Future<void> enqueueUpload({
    required ChatMessage msg,
    required String chatId,
    String cloudName = '',
    String uploadPreset = '',
  }) async {
    try {
      final media = msg.media;
      if (media == null || media.url.isEmpty) {
        debugPrint('[BGUpload] ❌ No media or empty path for msg=${msg.id}');
        return;
      }

      final taskId = 'upload-${msg.id}';

      debugPrint('[BGUpload] ➕ Enqueue media upload id=${msg.id}');

      await Workmanager().registerOneOffTask(
        taskId,
        _mediaTask,
        inputData: {
          'filePath': media.url,
          'chatId': chatId,
          'messageId': msg.id,
          'kind': media.kind.name,
          'accountId': msg.senderId,
          'cloudName': cloudName,
          'uploadPreset': uploadPreset,
        },
        constraints: Constraints(networkType: NetworkType.connected),
      );

      debugPrint('[BGUpload] ✅ Media task enqueued id=${msg.id}');
    } catch (e, st) {
      debugPrint('[BGUpload] ❌ Media enqueue failed');
      debugPrint(e.toString());
      debugPrint(st.toString());
    }
  }

  static Future<void> enqueueAvatarUpload({
    required String ownerType,
    required String ownerId,
    required String filePath,
    String cloudName = '',
    String uploadPreset = '',
  }) async {
    // 🔥 DEBUG #1 — confirms ProfileController reached here
    debugPrint('[BGUpload] enqueueAvatarUpload called');

    try {
      // ------------------------------------------------------------
      // VALIDATION
      // ------------------------------------------------------------
      if (filePath.isEmpty) {
        debugPrint('[BGUpload] ❌ Empty avatar filePath');
        return;
      }

      if (ownerType != 'user' && ownerType != 'group') {
        debugPrint('[BGUpload] ❌ Invalid ownerType=$ownerType');
        return;
      }

      final taskId = 'avatar-$ownerType-$ownerId';

      // 🔥 DEBUG #2 — confirms WorkManager registration attempt
      debugPrint(
        '[BGUpload] ➕ Enqueue avatar upload ownerType=$ownerType ownerId=$ownerId',
      );

      // ------------------------------------------------------------
      // WORKMANAGER TASK REGISTRATION
      // ------------------------------------------------------------
      await Workmanager().registerOneOffTask(
        taskId,
        _avatarTask, // == 'upload_avatar'
        inputData: {
          'ownerType': ownerType,
          'ownerId': ownerId,
          'filePath': filePath,
          'cloudName': cloudName,
          'uploadPreset': uploadPreset,
        },

        constraints: Constraints(networkType: NetworkType.connected),
      );

      // 🔥 DEBUG #3 — confirms task successfully registered
      debugPrint(
        '[BGUpload] ✅ Avatar task registered ownerType=$ownerType ownerId=$ownerId',
      );
    } catch (e, st) {
      debugPrint('[BGUpload] ❌ Avatar enqueue failed');
      debugPrint(e.toString());
      debugPrint(st.toString());
    }
  }

  // ------------------------------------------------------------
  // CANCEL
  // ------------------------------------------------------------

  /// Cancel a pending background upload (chat media only)
  static Future<void> cancelUpload(String messageId) async {
    final taskId = 'upload-$messageId';

    try {
      debugPrint('[BGUpload] ✖ Cancel $taskId');
      await Workmanager().cancelByUniqueName(taskId);
    } catch (e, st) {
      debugPrint('[BGUpload] ❌ Cancel failed $taskId');
      debugPrint(e.toString());
      debugPrint(st.toString());
    }
  }
}
