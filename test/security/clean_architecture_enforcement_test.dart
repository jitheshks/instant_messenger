import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 5.3 Enforced Clean Architecture Tests', () {
    final legacyDirectories = [
      'lib/controller',
      'lib/models',
      'lib/services',
      'lib/view',
      'lib/widgets',
      'lib/utils',
      'lib/theme',
      'lib/app_router',
      'lib/shared/controllers',
      'lib/core/theme',
    ];

    final legacyImportPrefixes = [
      'package:instant_messenger/controller/',
      'package:instant_messenger/models/',
      'package:instant_messenger/services/',
      'package:instant_messenger/view/',
      'package:instant_messenger/widgets/',
      'package:instant_messenger/utils/',
      'package:instant_messenger/theme/',
      'package:instant_messenger/app_router/',
      'package:instant_messenger/shared/controllers/',
      'package:instant_messenger/core/theme/',
    ];

    test('All legacy directories are deleted from filesystem', () {
      final existingLegacyDirs = <String>[];
      for (final dirPath in legacyDirectories) {
        if (Directory(dirPath).existsSync()) {
          existingLegacyDirs.add(dirPath);
        }
      }
      expect(
        existingLegacyDirs,
        isEmpty,
        reason:
            'Legacy directories must be completely removed: $existingLegacyDirs',
      );
    });

    test('Zero production and test files import from removed legacy paths', () {
      final violations = <String>[];
      final targetDirs = [Directory('lib'), Directory('test')];

      for (final dir in targetDirs) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith(
                'clean_architecture_enforcement_test.dart',
              )) {
            final lines = entity.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trim();
              if (trimmed.startsWith('import ') ||
                  trimmed.startsWith('export ')) {
                for (final prefix in legacyImportPrefixes) {
                  if (trimmed.contains(prefix)) {
                    violations.add('${entity.path}:${i + 1} $trimmed');
                  }
                }
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Found imports referencing legacy paths: $violations',
      );
    });

    test(
      'Domain layer purity: No dependencies on UI, Riverpod, Supabase, Data, or Presentation',
      () {
        final violations = <String>[];
        final libDir = Directory('lib');

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              entity.path.contains('/domain/')) {
            final lines = entity.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.startsWith('import ') || line.startsWith('export ')) {
                if (line.contains('package:flutter/') &&
                    !line.contains('package:flutter/foundation.dart')) {
                  violations.add(
                    '${entity.path}:${i + 1} imports Flutter UI: $line',
                  );
                }
                if (line.contains('package:flutter_riverpod')) {
                  violations.add(
                    '${entity.path}:${i + 1} imports Riverpod: $line',
                  );
                }
                if (line.contains('package:supabase')) {
                  violations.add(
                    '${entity.path}:${i + 1} imports Supabase: $line',
                  );
                }
                if (line.contains('/data/')) {
                  violations.add(
                    '${entity.path}:${i + 1} imports Data layer: $line',
                  );
                }
                if (line.contains('/presentation/')) {
                  violations.add(
                    '${entity.path}:${i + 1} imports Presentation layer: $line',
                  );
                }
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Domain entities must be pure Dart without UI, Riverpod, Supabase, Data, or Presentation: $violations',
        );
      },
    );

    test(
      'Data layer purity: Data does not depend on Presentation controllers or widgets',
      () {
        final violations = <String>[];
        final libDir = Directory('lib');

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              entity.path.contains('/data/')) {
            final lines = entity.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.startsWith('import ') || line.startsWith('export ')) {
                if (line.contains('/presentation/')) {
                  violations.add(
                    '${entity.path}:${i + 1} Data imports Presentation: $line',
                  );
                }
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Data layer must not depend on Presentation controllers or widgets: $violations',
        );
      },
    );

    test(
      'Shared layer purity: Shared components do not import feature implementations',
      () {
        final violations = <String>[];
        final sharedDir = Directory('lib/shared');

        if (sharedDir.existsSync()) {
          for (final entity in sharedDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('.dart')) {
              final lines = entity.readAsLinesSync();
              for (var i = 0; i < lines.length; i++) {
                final line = lines[i].trim();
                if (line.startsWith('import ') || line.startsWith('export ')) {
                  if (line.contains('/features/')) {
                    violations.add(
                      '${entity.path}:${i + 1} Shared imports Feature: $line',
                    );
                  }
                }
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Shared must remain strictly feature-independent: $violations',
        );
      },
    );

    test(
      'Riverpod 3.x modern pattern enforcement: Zero legacy providers across lib/',
      () {
        final forbiddenPatterns = [
          'package:flutter_riverpod/legacy.dart',
          'ChangeNotifierProvider',
          'StateNotifierProvider',
          'StateProvider',
          'StateNotifier',
        ];
        final violations = <String>[];
        final libDir = Directory('lib');

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final content = entity.readAsStringSync();
            for (final pattern in forbiddenPatterns) {
              if (content.contains(pattern)) {
                violations.add('${entity.path} contains $pattern');
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Only modern Riverpod 3.x patterns allowed (no legacy providers): $violations',
        );
      },
    );

    test('Core layer purity: Core does not import presentation layer', () {
      final violations = <String>[];
      final coreDir = Directory('lib/core');

      for (final entity in coreDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.startsWith('import ') || line.startsWith('export ')) {
              if (line.contains('/presentation/')) {
                violations.add(
                  '${entity.path}:${i + 1} Core imports Presentation: $line',
                );
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Core infrastructure must never import outer presentation layers: $violations',
      );
    });

    test(
      'ChatScreenController decomposition: Zero references in production lib/',
      () {
        final violations = <String>[];
        final libDir = Directory('lib');

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final content = entity.readAsStringSync();
            if (content.contains('ChatScreenController')) {
              violations.add('${entity.path} contains ChatScreenController');
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'ChatScreenController must be completely decomposed with 0 references in lib/: $violations',
        );
      },
    );

    test(
      'Account-scoped Hive boxes: Zero un-scoped Hive box opens in production code',
      () {
        final violations = <String>[];
        final libDir = Directory('lib');
        final forbiddenPatterns = [
          "openBox<ChatMessage>('messages')",
          "openBox('messages')",
          'openBox<ChatMessage>("messages")',
          'openBox("messages")',
        ];

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            // Exclude LegacyChatCacheMigration which exists specifically to migrate old data
            if (entity.path.contains('legacy_chat_cache_migration.dart') ||
                entity.path.contains('message_cache.dart')) {
              continue;
            }
            final content = entity.readAsStringSync();
            for (final pattern in forbiddenPatterns) {
              if (content.contains(pattern)) {
                violations.add('${entity.path} contains $pattern');
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'All Hive message boxes must be account-scoped to prevent isolate corruption: $violations',
        );
      },
    );

    test(
      'ChatRepository alias elimination: Zero mentions of ChatRepository in lib/ and test/',
      () {
        final violations = <String>[];
        final targetDirs = [Directory('lib'), Directory('test')];

        for (final dir in targetDirs) {
          for (final entity in dir.listSync(recursive: true)) {
            if (entity is File &&
                entity.path.endsWith('.dart') &&
                !entity.path.endsWith(
                  'clean_architecture_enforcement_test.dart',
                )) {
              final content = entity.readAsStringSync();
              if (content.contains('ChatRepository')) {
                violations.add('${entity.path} contains ChatRepository');
              }
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'ChatRepository must be completely replaced by MessagesRepository: $violations',
        );
      },
    );

    test(
      'Obsolete compatibility shims and legacy controller files must not exist',
      () {
        final forbiddenFiles = [
          'lib/features/messaging/data/chat_repository.dart',
          'lib/features/chats/presentation/controllers/chats_tab_controller.dart',
          'lib/features/contacts/presentation/controllers/contacts_screen_controller.dart',
          'lib/features/messaging/presentation/controllers/chat_media_controller.dart',
          'lib/features/messaging/presentation/controllers/chat_presence_controller.dart',
          'lib/features/messaging/presentation/controllers/chat_typing_controller.dart',
          'lib/core/providers/app_providers.dart',
          'lib/shared/utils/chat_id.dart',
          'lib/theme/theme.dart',
        ];

        final existingForbidden = <String>[];
        for (final path in forbiddenFiles) {
          if (File(path).existsSync()) {
            existingForbidden.add(path);
          }
        }

        expect(
          existingForbidden,
          isEmpty,
          reason:
              'Legacy compatibility files must be completely removed: $existingForbidden',
        );
      },
    );
  });
}
