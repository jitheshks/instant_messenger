import 'dart:ui';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/app.dart';
import 'package:instant_messenger/app/bootstrap/app_lifecycle_service.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/features/media/data/background_upload_executor.dart';
import 'package:instant_messenger/features/notifications/data/fcm_service.dart';
import 'package:instant_messenger/features/notifications/data/notification_service.dart';
import 'package:instant_messenger/features/notifications/data/onesignal_service.dart';
import 'package:workmanager/workmanager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
    // Ensure unhandled framework errors are logged to the debug console
    FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint('[FlutterError Stack] ${details.stack}');
    }
  };

  // Log unhandled asynchronous errors without blanket suppression
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformDispatcher Unhandled Async] $error');
    debugPrint('[PlatformDispatcher Stack] $stack');
    return false; // Do not suppress; allow normal error boundaries & reporting
  };

  // Load centralized environment configuration (.env)
  try {
    await AppConfig.initialize();
    final appId = AppConfig.current.oneSignalAppId.trim();
    if (appId.isNotEmpty) {
      OneSignalService.initializeEarly(appId);
    }
  } catch (e) {
    debugPrint('[main] AppConfig initialization notice: $e');
  }

  // Initialize Supabase client
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('[main] SupabaseConfig initialization notice: $e');
  }

  // Initialize Hive, register adapters, open base boxes safely
  try {
    await HiveInit.initAndOpenBoxes(
      boxesToOpen: ['profile', 'contacts', 'chats_meta'],
      suspectBoxesToDelete: ['chats_meta'],
    );
  } catch (e) {
    debugPrint('[main] HiveInit initialization notice: $e');
  }

  // Attempt to load saved theme mode from SharedPreferences, falling back
  // gracefully to system default if platform channel fails.
  AdaptiveThemeMode? savedMode;
  try {
    savedMode = await AdaptiveTheme.getThemeMode();
  } catch (e, stackTrace) {
    debugPrint(
      '[main] Failed to load saved theme mode from AdaptiveTheme (SharedPreferences): $e\n'
      'Defaulting to AdaptiveThemeMode.system.\n$stackTrace',
    );
    savedMode = AdaptiveThemeMode.system;
  }

  AppLifecycleService().register();

  // Initialize background and notification services concurrently to prevent serial UI isolate delays
  try {
    await Future.wait([
      Workmanager().initialize(callbackDispatcher).catchError((e) {
        debugPrint('[main] Workmanager initialization notice: $e');
      }),
      NotificationService.init().catchError((e) {
        debugPrint('[main] NotificationService initialization notice: $e');
      }),
      FcmService.registerBackgroundHandler().catchError((e) {
        debugPrint('[main] FcmService background handler notice: $e');
      }),
      FcmService.checkColdStartTap().catchError((e) {
        debugPrint('[main] FcmService cold-start tap check notice: $e');
      }),
    ]);
  } catch (e) {
    debugPrint('[main] Background services initialization notice: $e');
  }

  runApp(
    ProviderScope(
      child: MyApp(
        savedMode: savedMode,
      ),
    ),
  );
}


