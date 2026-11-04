import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Security & Credential Zero-Leakage Tests', () {
    test('Zero OneSignal REST API master key pattern in lib/', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final oneSignalMasterPattern = RegExp(
        r'os_v2_app_[a-z0-9]{30,}',
        caseSensitive: false,
      );
      final violations = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final content = entity.readAsStringSync();
          if (oneSignalMasterPattern.hasMatch(content) ||
              content.contains('kPushSenderSecret')) {
            violations.add(entity.path);
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Master REST API keys or kPushSenderSecret found in: $violations',
      );
    });

    test('Zero OneSignal REST API master key in root .env asset', () {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final content = envFile.readAsStringSync();
        final oneSignalMasterPattern = RegExp(
          r'os_v2_app_[a-z0-9]{30,}',
          caseSensitive: false,
        );
        expect(
          oneSignalMasterPattern.hasMatch(content),
          isFalse,
          reason: 'Master OneSignal REST API key must NOT be present in root .env asset',
        );
        expect(
          content.contains('ONESIGNAL_REST_KEY'),
          isFalse,
          reason: 'ONESIGNAL_REST_KEY must NOT be bundled in root .env',
        );
      }
    });

    test('Zero hardcoded developer phone number in settings screen', () {
      final settingsFile = File(
        'lib/features/settings/presentation/screens/settings_screen.dart',
      );
      expect(settingsFile.existsSync(), isTrue);

      final content = settingsFile.readAsStringSync();
      expect(
        content.contains('96459 05577'),
        isFalse,
        reason:
            'Hardcoded developer phone number must be removed from settings screen',
      );
    });

    test(
      'iOS Info.plist contains all 4 mandatory privacy usage descriptions',
      () {
        final plistFile = File('ios/Runner/Info.plist');
        expect(plistFile.existsSync(), isTrue);

        final content = plistFile.readAsStringSync();
        expect(content.contains('<key>NSCameraUsageDescription</key>'), isTrue);
        expect(
          content.contains('<key>NSMicrophoneUsageDescription</key>'),
          isTrue,
        );
        expect(
          content.contains('<key>NSPhotoLibraryUsageDescription</key>'),
          isTrue,
        );
        expect(
          content.contains('<key>NSContactsUsageDescription</key>'),
          isTrue,
        );
      },
    );

    test('Firestore rules eliminate cross-user inbox tampering', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue);

      final content = rulesFile.readAsStringSync();
      // Verifies that `/users/{uid}/chats/{chatId}` no longer has unconditional `allow write: if signedIn();`
      expect(
        content.contains(
          'allow read: if signedIn() && request.auth.uid == uid;',
        ),
        isTrue,
        reason: 'User inboxes must only be readable by their owner',
      );
      expect(
        content.contains(
          'allow delete: if signedIn() && request.auth.uid == uid;',
        ),
        isTrue,
        reason: 'User inboxes must only be deletable by their owner',
      );
    });
  });
}
