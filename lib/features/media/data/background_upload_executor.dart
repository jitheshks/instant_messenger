import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/media/data/background_upload_handoff.dart';
import 'package:instant_messenger/features/media/data/media_storage_service.dart';
import 'package:instant_messenger/features/media/data/supabase_storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

// background_upload_executor

/// 🚨 REQUIRED:
/// - top-level
/// - public
/// - @pragma('vm:entry-point')
@pragma('vm:entry-point')
void callbackDispatcher() {
  // 🔥 Required for plugins / HTTP / file IO in background isolate
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  Workmanager().executeTask((task, input) async {
    debugPrint('[BG] ▶ Task received: $task');

    // 1️⃣ Backend Configuration & Target Initialization
    if (!SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.initialize();
      } catch (e) {
        debugPrint('[BG] ❌ Supabase background init failed: $e');
        return false;
      }
    }

    // 2️⃣ Resolve Unified MediaStorageService
    final MediaStorageService storage = SupabaseStorageService();

    // ============================================================
    // 🟢 TASK: CHAT MEDIA UPLOAD
    // ============================================================
    if (task == 'upload_media') {
      final filePath = input?['filePath'] as String?;
      final chatId = input?['chatId'] as String?;
      final messageId = input?['messageId'] as String?;
      final kind = input?['kind'] as String?;
      final accountId = ((input?['accountId'] as String?)?.isNotEmpty == true)
          ? (input!['accountId'] as String)
          : (Supabase.instance.client.auth.currentUser?.id ?? '');

      if (filePath == null ||
          chatId == null ||
          messageId == null ||
          kind == null) {
        debugPrint('[BG] ❌ Missing media task data');
        return false;
      }

      try {
        debugPrint('[BG] ▶ Media upload start chatId=$chatId msg=$messageId');

        final result = await storage.uploadChatAttachment(
          chatId: chatId,
          messageId: messageId,
          filePath: filePath,
          mediaKind: kind,
        );

        try {
          await Supabase.instance.client.rpc(
            'attach_message_media',
            params: {
              'p_chat_id': chatId,
              'p_message_id': messageId,
              'p_media': {
                'url': result.publicUrl,
                'mime': result.mimeType,
                'size': result.fileSizeBytes,
                'kind': kind,
              },
            },
          );
        } catch (e) {
          debugPrint('[BG] ⚠️ Remote Supabase message update error: $e');
        }

        // 3️⃣ Durable Handoff to Foreground Isolate (Single-Writer Invariant Preserved)
        if (accountId.isNotEmpty) {
          await BackgroundUploadHandoff.recordCompletion(
            accountId: accountId,
            messageId: messageId,
            chatId: chatId,
            publicUrl: result.publicUrl,
            mimeType: result.mimeType,
            fileSizeBytes: result.fileSizeBytes,
            kind: kind,
          );
        }

        debugPrint('[BG] ✅ Media upload completed msg=$messageId');
        return true;
      } catch (e, st) {
        debugPrint('[BG] ❌ Media upload failed msg=$messageId: $e');
        debugPrint(st.toString());

        if (accountId.isNotEmpty) {
          await BackgroundUploadHandoff.recordFailure(
            accountId: accountId,
            messageId: messageId,
            chatId: chatId,
            errorMessage: e.toString(),
          );
        }

        return false;
      }
    }

    // ============================================================
    // 🟢 TASK: AVATAR UPLOAD
    // ============================================================
    if (task == 'upload_avatar') {
      final filePath = input?['filePath'] as String?;
      final ownerType = input?['ownerType'] as String?;
      final ownerId = input?['ownerId'] as String?;

      if (filePath == null || ownerType == null || ownerId == null) {
        debugPrint('[BG] ❌ Missing avatar task data');
        return false;
      }

      if (ownerType != 'user' && ownerType != 'group') {
        debugPrint('[BG] ❌ Invalid ownerType: $ownerType');
        return false;
      }

      try {
        debugPrint('[BG] 🚀 Avatar upload start owner=$ownerType/$ownerId');

        final result = await storage.uploadAvatar(
          ownerType: ownerType,
          ownerId: ownerId,
          filePath: filePath,
        );

        final avatarUrl = result.publicUrl;

        if (ownerType == 'user') {
          await Supabase.instance.client
              .from('profiles')
              .update({
                'avatar_url': avatarUrl,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', ownerId);
        } else {
          await Supabase.instance.client
              .from('chats')
              .update({
                'avatar_url': avatarUrl,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', ownerId);
        }

        debugPrint('[BG] ✅ Avatar upload completed owner=$ownerType/$ownerId');
        return true;
      } catch (e, st) {
        debugPrint('[BG] ❌ Avatar upload failed: $e');
        debugPrint(st.toString());
        return false;
      }
    }

    // ------------------------------------------------------------
    // UNKNOWN TASK
    // ------------------------------------------------------------
    debugPrint('[BG] ❌ Unknown task: $task');
    return false;
  });
}
