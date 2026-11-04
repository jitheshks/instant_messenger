import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:instant_messenger/features/media/data/background_upload_executor.dart';
import 'package:instant_messenger/features/media/data/background_upload_handoff.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundUploadExecutor Configuration & Lifecycle Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppConfig.overrideForTesting(null);
      SupabaseConfig.resetForTesting();
    });

    tearDown(() {
      AppConfig.overrideForTesting(null);
      SupabaseConfig.resetForTesting();
    });

    test('Zero dotenv or .env references in background_upload_executor.dart', () {
      final file = File(
        'lib/features/media/data/background_upload_executor.dart',
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(
        content.contains('dotenv'),
        isFalse,
        reason:
            'background_upload_executor.dart must not contain runtime dotenv references',
      );
      expect(
        content.contains("'.env'"),
        isFalse,
        reason:
            'background_upload_executor.dart must not load .env file directly',
      );
    });

    test('callbackDispatcher executes and registers top-level entry point', () {
      expect(callbackDispatcher, isNotNull);
      // Invoking callbackDispatcher in test environment registers Workmanager handler without throwing
      expect(() => callbackDispatcher(), returnsNormally);
    });

    test(
      'SupabaseConfig initialization succeeds in background with AppConfig override',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'https://bg-test.supabase.co',
            supabasePublishableKey: 'bg-test-key',
          ),
        );

        bool initializerInvoked = false;
        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          initializerInvoked = true;
          expect(url, equals('https://bg-test.supabase.co'));
          expect(anonKey, equals('bg-test-key'));
        });

        await SupabaseConfig.initialize();

        expect(initializerInvoked, isTrue);
        expect(SupabaseConfig.isInitialized, isTrue);
        expect(
          SupabaseConfig.configuredUrl,
          equals('https://bg-test.supabase.co'),
        );
      },
    );

    test(
      'Zero hardcoded messages Hive box in background_upload_executor.dart',
      () {
        final file = File(
          'lib/features/media/data/background_upload_executor.dart',
        );
        final content = file.readAsStringSync();
        expect(
          content.contains("'messages'"),
          isFalse,
          reason:
              'background_upload_executor.dart must not open or write to hardcoded un-scoped "messages" box',
        );
      },
    );

    test(
      'BackgroundUploadHandoff records and drains completion events per account',
      () async {
        await BackgroundUploadHandoff.recordCompletion(
          accountId: 'user_123',
          messageId: 'msg_abc',
          chatId: 'chat_xyz',
          publicUrl: 'https://example.com/photo.jpg',
          mimeType: 'image/jpeg',
          fileSizeBytes: 1024,
          kind: 'image',
        );

        final events = await BackgroundUploadHandoff.drainForAccount(
          'user_123',
        );
        expect(events.length, equals(1));
        expect(events.first.accountId, equals('user_123'));
        expect(events.first.messageId, equals('msg_abc'));
        expect(events.first.isSuccess, isTrue);
        expect(events.first.publicUrl, equals('https://example.com/photo.jpg'));

        // Subsequent drain must be empty (durable handoff consumed)
        final drainedAgain = await BackgroundUploadHandoff.drainForAccount(
          'user_123',
        );
        expect(drainedAgain, isEmpty);
      },
    );

    test('BackgroundUploadHandoff enforces account isolation', () async {
      await BackgroundUploadHandoff.recordCompletion(
        accountId: 'account_A',
        messageId: 'msg_1',
        chatId: 'chat_1',
        publicUrl: 'https://example.com/1.jpg',
        mimeType: 'image/jpeg',
        fileSizeBytes: 500,
        kind: 'image',
      );
      await BackgroundUploadHandoff.recordFailure(
        accountId: 'account_B',
        messageId: 'msg_2',
        chatId: 'chat_2',
        errorMessage: 'Network timeout',
      );

      final eventsA = await BackgroundUploadHandoff.drainForAccount(
        'account_A',
      );
      expect(eventsA.length, equals(1));
      expect(eventsA.first.messageId, equals('msg_1'));
      expect(eventsA.first.isSuccess, isTrue);

      final eventsB = await BackgroundUploadHandoff.drainForAccount(
        'account_B',
      );
      expect(eventsB.length, equals(1));
      expect(eventsB.first.messageId, equals('msg_2'));
      expect(eventsB.first.isSuccess, isFalse);
      expect(eventsB.first.errorMessage, equals('Network timeout'));
    });
  });
}
