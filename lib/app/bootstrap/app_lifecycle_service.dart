import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/features/messaging/data/outbox_service.dart';
import 'package:instant_messenger/features/media/data/background_upload_resync.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._();

  bool _registered = false;
  OutboxService? _outbox;

  /// attach after bootstrap
  void attachOutbox(OutboxService outbox) {
    _outbox = outbox;
  }

  void register() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;

    if (kDebugMode) {
      debugPrint('[Lifecycle] registered');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = SupabaseConfig.currentUserId;
    if (uid != null) {
      try {
        unawaited(
          Supabase.instance.client
              .from('profiles')
              .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
              .eq('id', uid)
              .catchError((err, st) {
                if (kDebugMode) {
                  debugPrint(
                    '[AppLifecycleService] last_seen update notice: $err',
                  );
                }
              }),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[AppLifecycleService] synchronous last_seen notice: $e',
          );
        }
      }
    }

    // Catch-up synchronization and Realtime probe when returning to foreground
    if (state == AppLifecycleState.resumed) {
      final db = HiveDatabaseManager.instance.activeDatabase;
      if (db?.realtimeConnectionManager != null) {
        unawaited(
          db!.realtimeConnectionManager!.onAppResumed().catchError((err, st) {
            if (kDebugMode) {
              debugPrint(
                '[AppLifecycleService] resume realtime probe notice: $err',
              );
            }
          }),
        );
      } else if (db?.reconciliationService != null) {
        unawaited(
          db!.reconciliationService!.syncMessages().catchError((err, st) {
            if (kDebugMode) {
              debugPrint('[AppLifecycleService] resume sync notice: $err');
            }
            return 0;
          }),
        );
      }
    }

    // 🔥 THIS is where resync happens
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _outbox != null) {
      unawaited(
        BackgroundUploadResync.resync(_outbox!).catchError((err, st) {
          if (kDebugMode) {
            debugPrint('[AppLifecycleService] resync notice: $err');
          }
        }),
      );
    }
  }
}
