// lib/services/hive_init.dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:instant_messenger/models/chat_message.dart';

/// Centralized Hive initialization & recovery
class HiveInit {
  /// Register ALL Hive adapters used in the app
  static void registerAdapters() {
    // ---------------- ENUMS ----------------
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(DeliveryStateAdapter());
    }

    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MessageTypeAdapter());
    }

    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MediaKindAdapter());
    }

    // ---------------- CLASSES ----------------
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(MessageMediaAdapter());
    }

    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
  }

  /// Initialize Hive + open base boxes safely
  static Future<void> initAndOpenBoxes({
    List<String>? boxesToOpen,
    List<String>? suspectBoxesToDelete,
  }) async {
    final defaultBoxes =
        boxesToOpen ?? <String>['profile', 'contacts', 'chats_meta'];
    final suspectBoxes =
        suspectBoxesToDelete ?? <String>['chats_meta'];

    // 1️⃣ Init Hive
    await Hive.initFlutter();

    // 2️⃣ Register adapters BEFORE opening boxes
    registerAdapters();

    // 3️⃣ Try opening boxes
    try {
      for (final name in defaultBoxes) {
        if (!Hive.isBoxOpen(name)) {
          await Hive.openBox(name);
        }
      }
      if (kDebugMode) {
        debugPrint('[HiveInit] opened boxes: $defaultBoxes');
      }
      return;
    } on HiveError catch (e) {
      final msg = e.toString();
      debugPrint('[HiveInit] HiveError: $msg');

      // 🔥 Targeted recovery for unknown typeId
      if (msg.contains('unknown typeId')) {
        debugPrint('[HiveInit] unknown typeId → recovering');

        try {
          await Hive.close();
        } catch (_) {}

        for (final box in suspectBoxes) {
          try {
            await Hive.deleteBoxFromDisk(box);
            debugPrint('[HiveInit] deleted suspect box: $box');
          } catch (_) {}
        }

        await Hive.initFlutter();
        registerAdapters();

        for (final name in defaultBoxes) {
          if (!Hive.isBoxOpen(name)) {
            await Hive.openBox(name);
          }
        }

        debugPrint('[HiveInit] recovery complete');
        return;
      }

      rethrow;
    }
  }
}
