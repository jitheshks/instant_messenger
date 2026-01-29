import 'package:hive/hive.dart';
import '../models/chat_message.dart';

class OutboxProgressStore {
  static const String boxName = 'outbox';

  /// 🔥 Safe to call from background isolate
  static Future<void> updateProgress(
    String messageId,
    double progress,
  ) async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<ChatMessage>(boxName);
    }

    final box = Hive.box<ChatMessage>(boxName);
    final msg = box.get(messageId);
    if (msg == null) return;

    await box.put(
      messageId,
      msg.copyWith(uploadProgress: progress),
    );
  }
}
