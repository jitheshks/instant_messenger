import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/bootstrap/app_lifecycle_service.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/messaging/data/outbox_service.dart';

class _FakeFailingOutboxService implements OutboxService {
  @override
  String get cloudName => 'test_cloud';

  @override
  String get uploadPreset => 'test_preset';

  @override
  String? get currentUserId => 'user-test-uid';

  @override
  Future<List<ChatMessage>> getPendingUploads() async {
    throw Exception('Simulated outbox storage failure during app pause/detach');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleService and Error Handling Tests', () {
    test(
      'didChangeAppLifecycleState gracefully handles asynchronous errors during paused and detached states',
      () async {
        final lifecycleService = AppLifecycleService();
        lifecycleService.register();
        lifecycleService.attachOutbox(_FakeFailingOutboxService());

        // Changing state to paused when offline or backend fails should not throw
        expect(
          () => lifecycleService.didChangeAppLifecycleState(
            AppLifecycleState.paused,
          ),
          returnsNormally,
        );

        // Changing state to detached should also not throw
        expect(
          () => lifecycleService.didChangeAppLifecycleState(
            AppLifecycleState.detached,
          ),
          returnsNormally,
        );

        // Changing state to resumed should not throw
        expect(
          () => lifecycleService.didChangeAppLifecycleState(
            AppLifecycleState.resumed,
          ),
          returnsNormally,
        );
      },
    );

    test(
      'SupabaseConfig.currentUserId is null-safe when uninitialized or offline',
      () {
        expect(SupabaseConfig.currentUserId, isNull);
      },
    );
  });
}
