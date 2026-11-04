import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/core/config/app_config.dart';
import 'package:instant_messenger/core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupabaseConfig Target Selection Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      AppConfig.overrideForTesting(null);
      SupabaseConfig.resetForTesting();
    });

    tearDown(() {
      AppConfig.overrideForTesting(null);
      SupabaseConfig.resetForTesting();
    });

    test(
      'Throws StateError when environment configuration is missing',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(supabaseUrl: '', supabasePublishableKey: ''),
        );

        expect(
          () => SupabaseConfig.initialize(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Missing required Supabase environment configuration'),
            ),
          ),
        );
      },
    );

    test(
      'Throws FormatException when Supabase URL format is malformed',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'invalid-not-a-url',
            supabasePublishableKey: 'mock-anon-key-12345',
          ),
        );

        expect(
          () => SupabaseConfig.initialize(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Supabase URL format'),
            ),
          ),
        );
      },
    );

    test(
      'Throws FormatException when Supabase URL has no host (https://)',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'https://',
            supabasePublishableKey: 'mock-anon-key-12345',
          ),
        );

        expect(
          () => SupabaseConfig.initialize(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Supabase URL format'),
            ),
          ),
        );
      },
    );

    test(
      'Throws FormatException when Supabase URL has unsupported scheme (httpx://)',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'httpx://example.supabase.co',
            supabasePublishableKey: 'mock-anon-key-12345',
          ),
        );

        expect(
          () => SupabaseConfig.initialize(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Supabase URL format'),
            ),
          ),
        );
      },
    );

    test('Configures Supabase target when keys are set in environment', () {
      SupabaseConfig.setTargetForTesting(
        BackendTarget.supabase,
        initialized: true,
      );
      expect(SupabaseConfig.activeTarget, equals(BackendTarget.supabase));
      expect(SupabaseConfig.isSupabaseTarget, isTrue);
      expect(SupabaseConfig.isInitialized, isTrue);
    });

    test('AppConfig resolves fallback from SUPABASE_ANON_KEY in fromMap', () {
      final config = AppConfig.fromMap({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'fallback-anon-key',
      });

      expect(config.supabaseUrl, equals('https://example.supabase.co'));
      expect(config.supabasePublishableKey, equals('fallback-anon-key'));
      expect(config.isConfigured, isTrue);
    });

    test(
      'AppConfig validation fails safely without exposing keys in error',
      () {
        const config = AppConfig(
          supabaseUrl: '',
          supabasePublishableKey: 'secret-key-must-not-appear',
        );

        try {
          config.validate();
          fail('Expected StateError');
        } catch (e) {
          expect(e, isA<StateError>());
          final message = (e as StateError).message;
          expect(message, isNot(contains('secret-key-must-not-appear')));
        }
      },
    );

    test(
      'URL validation error does not include raw URL or sensitive tokens',
      () {
        const configWithToken = AppConfig(
          supabaseUrl: 'https://user:sensitive-token@',
          supabasePublishableKey: 'mock-key',
        );

        try {
          configWithToken.validate();
          fail('Expected FormatException');
        } catch (e) {
          expect(e, isA<FormatException>());
          final message = (e as FormatException).message;
          expect(message, isNot(contains('sensitive-token')));
          expect(message, isNot(contains('https://')));
        }
      },
    );

    test(
      'Explicit customConfig takes precedence over active AppConfig.overrideForTesting',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'https://override.supabase.co',
            supabasePublishableKey: 'override-key',
          ),
        );

        const customConfig = AppConfig(
          supabaseUrl: 'https://',
          supabasePublishableKey: 'custom-key',
        );

        expect(
          () => SupabaseConfig.initialize(customConfig),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Supabase URL format'),
            ),
          ),
        );
      },
    );

    test(
      'Explicit customConfig initializes client even when AppConfig.overrideForTesting is invalid',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(supabaseUrl: '', supabasePublishableKey: ''),
        );

        String? capturedUrl;
        String? capturedKey;
        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          capturedUrl = url;
          capturedKey = anonKey;
        });

        await SupabaseConfig.initialize(
          const AppConfig(
            supabaseUrl: 'https://custom.supabase.co',
            supabasePublishableKey: 'custom-key',
          ),
        );

        expect(capturedUrl, equals('https://custom.supabase.co'));
        expect(capturedKey, equals('custom-key'));
        expect(
          SupabaseConfig.configuredUrl,
          equals('https://custom.supabase.co'),
        );
        expect(SupabaseConfig.isInitialized, isTrue);
      },
    );

    test(
      'Active AppConfig.overrideForTesting is used when no customConfig is provided',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: '',
            supabasePublishableKey: 'override-key',
          ),
        );

        expect(
          () => SupabaseConfig.initialize(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Missing required Supabase environment configuration'),
            ),
          ),
        );
      },
    );

    test(
      'Active AppConfig.overrideForTesting successfully initializes SupabaseConfig',
      () async {
        AppConfig.overrideForTesting(
          const AppConfig(
            supabaseUrl: 'https://override-success.supabase.co',
            supabasePublishableKey: 'override-success-key',
          ),
        );

        String? capturedUrl;
        String? capturedKey;
        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          capturedUrl = url;
          capturedKey = anonKey;
        });

        await SupabaseConfig.initialize();

        expect(capturedUrl, equals('https://override-success.supabase.co'));
        expect(capturedKey, equals('override-success-key'));
        expect(
          SupabaseConfig.configuredUrl,
          equals('https://override-success.supabase.co'),
        );
        expect(SupabaseConfig.isInitialized, isTrue);
      },
    );

    test(
      'AppConfig hasAnySupabaseConfig detects presence of either URL or key',
      () {
        const empty = AppConfig(supabaseUrl: '', supabasePublishableKey: '');
        const urlOnly = AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: '',
        );
        const keyOnly = AppConfig(
          supabaseUrl: '',
          supabasePublishableKey: 'mock-key',
        );
        const full = AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'mock-key',
        );

        expect(empty.hasAnySupabaseConfig, isFalse);
        expect(urlOnly.hasAnySupabaseConfig, isTrue);
        expect(keyOnly.hasAnySupabaseConfig, isTrue);
        expect(full.hasAnySupabaseConfig, isTrue);
      },
    );

    test(
      'Partial custom configuration throws StateError when required keys are missing',
      () async {
        const partialConfig = AppConfig(
          supabaseUrl: 'https://staging.supabase.co',
          supabasePublishableKey: '',
        );

        expect(
          () => SupabaseConfig.initialize(partialConfig),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Missing required Supabase environment configuration'),
            ),
          ),
        );
      },
    );

    test(
      'Validation failure clears configuredUrl and sets isInitialized to false without invoking SDK',
      () async {
        SupabaseConfig.setTargetForTesting(
          BackendTarget.supabase,
          initialized: true,
          configuredUrl: 'https://prior.supabase.co',
        );

        bool initializerInvoked = false;
        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          initializerInvoked = true;
        });

        await expectLater(
          () => SupabaseConfig.initialize(
            const AppConfig(
              supabaseUrl: 'https://',
              supabasePublishableKey: 'mock-key',
            ),
          ),
          throwsA(isA<FormatException>()),
        );

        expect(initializerInvoked, isFalse);
        expect(SupabaseConfig.isInitialized, isFalse);
        expect(SupabaseConfig.configuredUrl, isNull);
      },
    );

    test(
      'SDK initialization failure clears configuredUrl and sets isInitialized to false',
      () async {
        SupabaseConfig.setTargetForTesting(
          BackendTarget.supabase,
          initialized: true,
          configuredUrl: 'https://prior.supabase.co',
        );

        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          throw Exception('Simulated client initialization failure');
        });

        await expectLater(
          () => SupabaseConfig.initialize(
            const AppConfig(
              supabaseUrl: 'https://valid.supabase.co',
              supabasePublishableKey: 'valid-key',
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Simulated client initialization failure'),
            ),
          ),
        );

        expect(SupabaseConfig.isInitialized, isFalse);
        expect(SupabaseConfig.configuredUrl, isNull);
      },
    );
  });

  group('Centralized Runtime .env Configuration Tests', () {
    setUp(() {
      AppConfig.resetForTesting();
      SupabaseConfig.resetForTesting();
    });

    tearDown(() {
      AppConfig.resetForTesting();
      SupabaseConfig.resetForTesting();
    });

    test(
      'Successful configuration loading through AppConfig.initialize',
      () async {
        final config = await AppConfig.initialize(
          customMap: {
            'SUPABASE_URL': 'https://custom-init.supabase.co',
            'SUPABASE_PUBLISHABLE_KEY': 'custom-key-xyz',
            'ONESIGNAL_APP_ID': 'custom-onesignal-id-999',
          },
        );

        expect(config.supabaseUrl, equals('https://custom-init.supabase.co'));
        expect(config.supabasePublishableKey, equals('custom-key-xyz'));
        expect(config.oneSignalAppId, equals('custom-onesignal-id-999'));
        expect(
          AppConfig.current.oneSignalAppId,
          equals('custom-onesignal-id-999'),
        );
        expect(AppConfig.isInitialized, isTrue);
      },
    );

    test(
      'Missing required configuration throws StateError without leaking keys',
      () async {
        expect(
          () => AppConfig.initialize(
            customMap: {
              'SUPABASE_URL': '',
              'SUPABASE_PUBLISHABLE_KEY': 'secret-key-1234',
            },
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Missing required Supabase environment configuration'),
            ),
          ),
        );
      },
    );

    test(
      'Invalid Supabase URL throws FormatException without leaking credentials',
      () async {
        expect(
          () => AppConfig.initialize(
            customMap: {
              'SUPABASE_URL': 'invalid-url-no-host',
              'SUPABASE_PUBLISHABLE_KEY': 'valid-key',
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Supabase URL format'),
            ),
          ),
        );
      },
    );

    test('OneSignal App ID is accessible through AppConfig.current', () async {
      await AppConfig.initialize(
        customMap: {
          'SUPABASE_URL': 'https://onesignal-access.supabase.co',
          'SUPABASE_PUBLISHABLE_KEY': 'onesignal-access-key',
          'ONESIGNAL_APP_ID': 'onesignal-app-id-777',
        },
      );

      expect(AppConfig.current.oneSignalAppId, equals('onesignal-app-id-777'));
    });

    test('Supabase initialization succeeds using AppConfig values', () async {
      String? capturedUrl;
      String? capturedKey;

      SupabaseConfig.setInitializerForTesting(({
        required String url,
        required String anonKey,
      }) async {
        capturedUrl = url;
        capturedKey = anonKey;
      });

      await AppConfig.initialize(
        customMap: {
          'SUPABASE_URL': 'https://live-flow.supabase.co',
          'SUPABASE_PUBLISHABLE_KEY': 'live-flow-key',
        },
      );

      await SupabaseConfig.initialize();

      expect(capturedUrl, equals('https://live-flow.supabase.co'));
      expect(capturedKey, equals('live-flow-key'));
      expect(
        SupabaseConfig.configuredUrl,
        equals('https://live-flow.supabase.co'),
      );
      expect(SupabaseConfig.isInitialized, isTrue);
    });

    test(
      'Background execution automatically triggers AppConfig.initialize if not yet initialized',
      () async {
        AppConfig.resetForTesting();
        SupabaseConfig.resetForTesting();

        String? capturedUrl;
        String? capturedKey;

        SupabaseConfig.setInitializerForTesting(({
          required String url,
          required String anonKey,
        }) async {
          capturedUrl = url;
          capturedKey = anonKey;
        });

        // In a background isolate, AppConfig is uninitialized.
        // Calling SupabaseConfig.initialize([customConfig]) or SupabaseConfig.initialize()
        // ensures AppConfig is initialized.
        const bgConfig = AppConfig(
          supabaseUrl: 'https://background-isolate.supabase.co',
          supabasePublishableKey: 'background-isolate-key',
        );

        await SupabaseConfig.initialize(bgConfig);

        expect(capturedUrl, equals('https://background-isolate.supabase.co'));
        expect(capturedKey, equals('background-isolate-key'));
        expect(SupabaseConfig.isInitialized, isTrue);
      },
    );

    test(
      'Ensuring application services do not maintain duplicate configuration sources',
      () {
        final bgFile = File(
          'lib/features/media/data/background_upload_executor.dart',
        );
        expect(
          bgFile.readAsStringSync().contains('dotenv'),
          isFalse,
          reason:
              'Background executor must not read dotenv directly; it must rely on centralized SupabaseConfig',
        );

        final oneSignalFile = File(
          'lib/features/notifications/data/onesignal_service.dart',
        );
        expect(
          oneSignalFile.readAsStringSync().contains('dotenv'),
          isFalse,
          reason:
              'OneSignalService must receive appId via parameter, not read dotenv',
        );

        final mainFile = File('lib/main.dart');
        expect(
          mainFile.readAsStringSync().contains(
            "import 'package:flutter_dotenv/flutter_dotenv.dart';",
          ),
          isFalse,
          reason:
              'main.dart must not import flutter_dotenv directly; it must use AppConfig.initialize()',
        );
      },
    );

    test(
      'pubspec.yaml declares flutter_dotenv and .env asset for automatic runtime loading',
      () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(
          pubspec.contains('flutter_dotenv:'),
          isTrue,
          reason: 'flutter_dotenv must be declared in pubspec.yaml',
        );

        final lines = pubspec.split('\n');
        final assetEnvLines = lines.where((l) {
          final trimmed = l.trim();
          return trimmed == '- .env' ||
              trimmed == '- \'.env\'' ||
              trimmed == '- ".env"';
        }).toList();
        expect(
          assetEnvLines,
          isNotEmpty,
          reason:
              '.env must be declared in pubspec.yaml assets so flutter_dotenv can load it automatically on devices',
        );
      },
    );
  });
}
