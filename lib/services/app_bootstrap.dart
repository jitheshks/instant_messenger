import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:instant_messenger/services/user_bootstrap.dart';
import '../models/chat_message.dart';
import '../services/outbox_service.dart';
import '../services/message_cache.dart';
import '../services/chat_repository.dart';

class AppBootstrapResult {
  final ChatRepository repo;
  final OutboxService outbox;
  final MessageCache cache;
  final Box<ChatMessage> outboxBox;
  final NextRoute nextRoute;
    final String displayName;
  AppBootstrapResult({
    required this.repo,
    required this.outbox,
    required this.cache,
    required this.outboxBox,
        required this.nextRoute,

            required this.displayName,
  });
}

Future<AppBootstrapResult> bootstrapAppServices({
  required String uid,
  required String cloudName,
  required String uploadPreset,
  required NextRoute nextRoute,
  required String displayName, 
}) async {
  await Hive.initFlutter();

  final outboxBox = await Hive.openBox<ChatMessage>('outbox_$uid');
  final outboxMeta = await Hive.openBox('outbox_meta');

  final cache = await MessageCache.open(uid: uid);
  final repo = ChatRepository(db: FirebaseFirestore.instance);

  final outbox = OutboxService(
    messageBox: outboxBox,
    metaBox: outboxMeta,
    cloudName: cloudName,
    uploadPreset: uploadPreset,
    messageCache: cache, 
  );

  return AppBootstrapResult(
    repo: repo,
    outbox: outbox,
    cache: cache,
    outboxBox: outboxBox,
     nextRoute: nextRoute,displayName: displayName,
  );
}
