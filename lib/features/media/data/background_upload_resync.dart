import 'package:flutter/foundation.dart';
import 'package:instant_messenger/features/media/data/background_upload_handoff.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/media/data/background_upload_scheduler.dart';

class BackgroundUploadResync {
  static Future<void> resync(
    OutboxService outbox, [
    String? currentUserId,
  ]) async {
    // 1️⃣ Process and apply any background upload handoffs for the current account
    final uid = currentUserId ?? outbox.currentUserId;
    if (uid != null && uid.isNotEmpty) {
      final events = await BackgroundUploadHandoff.drainForAccount(
        uid,
        onProcessEvent: (event) async {
          if (event.isSuccess) {
            await outbox.markUploadCompleted(
              messageId: event.messageId,
              publicUrl: event.publicUrl ?? '',
              mimeType: event.mimeType,
            );
          } else {
            await outbox.markUploadFailed(
              messageId: event.messageId,
              reason: event.errorMessage,
            );
          }
        },
      );
      if (events.isNotEmpty && kDebugMode) {
        debugPrint(
          '[Resync] Processed ${events.length} background upload handoff events',
        );
      }
    }

    // 2️⃣ Re-enqueue any remaining pending uploads
    final pending = await outbox.getPendingUploads();

    for (final msg in pending) {
      await BackgroundUploadScheduler.enqueueUpload(
        msg: msg,
        chatId: msg.chatId,
        cloudName: outbox.cloudName,
        uploadPreset: outbox.uploadPreset,
      );
    }

    if (kDebugMode) {
      debugPrint('[Resync] ${pending.length} uploads re-enqueued');
    }
  }
}
