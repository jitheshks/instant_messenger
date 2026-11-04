// lib/features/media/presentation/providers/media_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/app/bootstrap/app_bootstrap_providers.dart';
import 'package:instant_messenger/features/media/data/media_storage_service.dart';
import 'package:instant_messenger/features/media/data/supabase_storage_service.dart';
import 'package:instant_messenger/features/media/data/upload_orchestrator.dart';
import 'package:instant_messenger/features/media/presentation/controllers/gallery_picker_notifier.dart';
import 'package:instant_messenger/features/media/presentation/controllers/voice_recorder_notifier.dart';

final mediaStorageServiceProvider = Provider<MediaStorageService>((ref) {
  return SupabaseStorageService();
});

final uploadOrchestratorProvider = Provider<UploadOrchestrator?>((ref) {
  final outbox = ref.watch(outboxServiceProvider);
  if (outbox == null) return null;

  return UploadOrchestrator(
    storage: ref.watch(mediaStorageServiceProvider),
    outbox: outbox,
  );
});

final galleryPickerControllerProvider =
    NotifierProvider.autoDispose<GalleryPickerNotifier, GalleryPickerState>(
      GalleryPickerNotifier.new,
    );

final voiceRecorderServiceProvider =
    NotifierProvider.autoDispose<VoiceRecorderNotifier, VoiceRecordState>(
      VoiceRecorderNotifier.new,
    );
