// lib/features/calls/presentation/providers/calls_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/persistence/hive_database.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';

import '../../data/repositories/supabase_calls_repository.dart';
import '../../data/services/zego_engine_service_impl.dart';
import '../../domain/models/call_record.dart';
import '../../domain/models/zego_call_models.dart';
import '../../domain/repositories/calls_repository.dart';
import '../../domain/services/zego_engine_service.dart';
import '../controllers/call_controller.dart';
import '../controllers/calls_tab_notifier.dart';

/// Exposes the active [CallsRepository] implementation for audio/video calling.
final callsRepositoryProvider = Provider<CallsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final repo = SupabaseCallsRepository(client);
  final activeDb = HiveDatabaseManager.instance.activeDatabase;
  if (activeDb?.realtimeConnectionManager != null) {
    repo.attachConnectionManager(activeDb!.realtimeConnectionManager!);
  }
  return repo;
});

/// Exposes the centralized [ZegoEngineService] singleton.
final zegoEngineServiceProvider = Provider<ZegoEngineService>((ref) {
  final service = ZegoEngineServiceImpl();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Riverpod 3.x NotifierProvider exposing reactive calling session state.
final callControllerProvider =
    NotifierProvider<CallController, ZegoCallSession>(() {
  return CallController();
});

/// Exposes reactive state for the Calls tab history list.
final callsTabNotifierProvider =
    NotifierProvider<CallsTabNotifier, CallsTabState>(() {
  return CallsTabNotifier();
});

/// Exposes reactive stream of call records for a specific chat conversation.
final chatCallsProvider =
    StreamProvider.family<List<CallRecord>, String>((ref, chatId) {
  final repository = ref.watch(callsRepositoryProvider);
  return repository.watchCallsForChat(chatId);
});
