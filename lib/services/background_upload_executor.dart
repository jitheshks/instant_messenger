import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/services/uploads/cloudinary_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:instant_messenger/services/hive_init.dart';


import '../firebase_options.dart';

//background_uploader_executor

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

   // ------------------------------------------------------------
// FIREBASE INIT (BACKGROUND ISOLATE)
// ------------------------------------------------------------
try {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
} catch (e, st) {
  debugPrint('[BG] ❌ Firebase init failed');
  debugPrint(e.toString());
  debugPrint(st.toString());
  return false;
}

// 🔥 HIVE INIT (BACKGROUND SAFE)
await HiveInit.initAndOpenBoxes(
  boxesToOpen: ['messages'],
  suspectBoxesToDelete: ['messages'],
);


    // ------------------------------------------------------------
    // CLOUDINARY CONFIG
    // ------------------------------------------------------------
    final cloudName = input?['cloudName'] as String?;
    final uploadPreset = input?['uploadPreset'] as String?;

    if (cloudName == null || uploadPreset == null) {
      debugPrint('[BG] ❌ Missing Cloudinary credentials');
      return false;
    }


  final cloudinary = CloudinaryBackgroundService(
  cloudName: cloudName,
  uploadPreset: uploadPreset,
);
    final firestore = FirebaseFirestore.instance;

   // ============================================================
// 🟢 TASK: CHAT MEDIA UPLOAD (FIX)
// ============================================================
if (task == 'upload_media') {
  final filePath = input?['filePath'] as String?;
  final chatId = input?['chatId'] as String?;
  final messageId = input?['messageId'] as String?;
  final kind = input?['kind'] as String?;
  final isGroup = input?['isGroup'] as bool? ?? false;

  if (filePath == null ||
      chatId == null ||
      messageId == null ||
      kind == null) {
    debugPrint('[BG] ❌ Missing media task data');
    return false;
  }

  try {
    debugPrint('[BG] ▶ Media upload start chatId=$chatId msg=$messageId');

    final folder =
    'instant_messenger/chats/${isGroup ? 'groups' : 'direct'}/$chatId/$kind';

final resourceType = switch (kind) {
  'image' => 'image',
  'video' => 'video',
  'audio' => 'video',
  'document' => 'raw',
  _ => 'raw',
};

final result = await cloudinary.upload(
  filePath: filePath,
  folder: folder,
  resourceType: resourceType,
);

   // 🔥 Update Firestore (ONLY media + status int)
await firestore
    .collection('chats')
    .doc(chatId)
    .collection('messages')
    .doc(messageId)
    .update({
  'media.url': result['secure_url'],
  'media.mime': result['mime'],
  'status': 2, // delivered
  'updatedAt': FieldValue.serverTimestamp(),
});

// 🔥 UPDATE HIVE (THIS WAS MISSING)
final msgBox = Hive.isBoxOpen('messages')
    ? Hive.box<ChatMessage>('messages')
    : await Hive.openBox<ChatMessage>('messages');
final msg = msgBox.get(messageId);

if (msg != null) {
  await msgBox.put(
    messageId,
    msg.copyWith(
      failure: null,
deliveryState: DeliveryState.delivered,
      uploadProgress: null,
      media: msg.media?.copyWith(
        url: result['secure_url'],
        mime: result['mime'],
      ),
    ),
  );
}


    debugPrint('[BG] ✅ Media upload completed msg=$messageId');
    return true;
  } catch (e, st) {
    debugPrint('[BG] ❌ Media upload failed msg=$messageId');
    debugPrint(e.toString());
    debugPrint(st.toString());

// ❌ DO NOT update Firestore status on failure
// Firestore failure ≠ delivery failure

final msgBox = Hive.box<ChatMessage>('messages');
final msg = msgBox.get(messageId);

if (msg != null) {
  await msgBox.put(
    messageId,
    msg.copyWith(
      failure: MessageFailureReason.uploadFailed,
      uploadProgress: null,
    ),
  );
}

    return false;
  }
}


// ============================================================
// 🟢 TASK: AVATAR UPLOAD (FINAL FIX)
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

 final folder = ownerType == 'user'
    ? 'instant_messenger/avatars/users/$ownerId'
    : 'instant_messenger/avatars/groups/$ownerId';

final result = await cloudinary.upload(
  filePath: filePath,
  folder: folder,
  resourceType: 'image',
);

final avatarUrl = result['secure_url'];


// 🔥 SAVE URL TO FIRESTORE HERE
final collection = ownerType == 'user' ? 'users' : 'groups';

await firestore
    .collection(collection)
    .doc(ownerId)
    .update({
  'avatar_url': avatarUrl,
  'updated_at': FieldValue.serverTimestamp(),
});

debugPrint('[BG] ✅ Avatar upload completed owner=$ownerType/$ownerId');
return true;

  } catch (e, st) {
    debugPrint('[BG] ❌ Avatar upload failed');
    debugPrint(e.toString());
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
