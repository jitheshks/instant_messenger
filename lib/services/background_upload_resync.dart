import 'package:flutter/foundation.dart';
import 'package:instant_messenger/services/outbox_service.dart';
import 'package:instant_messenger/services/background_upload_scheduler.dart';

class BackgroundUploadResync {
  static Future<void> resync(OutboxService outbox) async {
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
