import 'package:hive_flutter/hive_flutter.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/sync/outbox_daemon.dart';
import 'package:instant_messenger/core/sync/reconciliation_service.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/messaging/data/message_cache.dart';
import 'package:instant_messenger/features/messaging/data/messages_repository.dart';

class AppBootstrapResult {
  final MessagesRepository repo;
  final OutboxService outbox;
  final MessageCache cache;
  final Box<ChatMessage> outboxBox;
  final NextRoute nextRoute;
  final String displayName;
  final HiveDatabase? database;

  OutboxDaemon? get outboxDaemon => database?.outboxDaemon;
  ReconciliationService? get reconciliationService =>
      database?.reconciliationService;

  AppBootstrapResult({
    required this.repo,
    required this.outbox,
    required this.cache,
    required this.outboxBox,
    required this.nextRoute,
    required this.displayName,
    this.database,
  });
}

Future<AppBootstrapResult> bootstrapAppServices({
  required String uid,
  String cloudName = '',
  String uploadPreset = '',
  required NextRoute nextRoute,
  required String displayName,
}) async {
  await Hive.initFlutter();

  // Open centralized HiveDatabase for this account (handles adapter registration,
  // chat_cache migration, and in-flight crash recovery)
  final database = await HiveDatabaseManager.instance.openAccount(uid);

  final outboxBox = await Hive.openBox<ChatMessage>('outbox_$uid');
  final outboxMeta = await Hive.openBox('outbox_meta');

  // Construct lightweight compatibility cache backed directly by account-scoped stores
  final cache = MessageCache.fromBoxes(
    database.messagesStore.box,
    null,
    200,
    database.chatsStore,
  );
  final repo = MessagesRepository(
    messagesStore: database.messagesStore,
    outboxDaemon: database.outboxDaemon,
    chatsStore: database.chatsStore,
  );

  final outbox = OutboxService(
    messageBox: outboxBox,
    metaBox: outboxMeta,
    cloudName: cloudName,
    uploadPreset: uploadPreset,
    messageCache: cache,
    chatsStore: database.chatsStore,
  );

  return AppBootstrapResult(
    repo: repo,
    outbox: outbox,
    cache: cache,
    outboxBox: outboxBox,
    nextRoute: nextRoute,
    displayName: displayName,
    database: database,
  );
}
