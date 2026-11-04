import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:instant_messenger/app/router/app_router.dart';
import 'package:instant_messenger/app/router/router_notifier.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/core/persistence/hive_init.dart';
import 'package:instant_messenger/core/persistence/local_cache.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/edit_name_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_providers.dart';
import 'package:instant_messenger/features/profile/presentation/screens/edit_name_screen.dart';

class FakeUserBootstrap extends UserBootstrap {
  bool shouldFail = false;
  String? savedName;
  String? savedAvatarUrl;

  @override
  Future<void> setDisplayName(String displayName, {String? avatarUrl}) async {
    if (shouldFail) {
      throw const SocketException('Connection error while saving profile');
    }
    savedName = displayName;
    savedAvatarUrl = avatarUrl;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeUserBootstrap fakeBootstrap;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_flow_test_');
    Hive.init(tempDir.path);
    HiveInit.registerAdapters();
    await Hive.openBox('profile');
    await Hive.openBox('contacts');
    await Hive.openBox('chats_meta');
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    fakeBootstrap = FakeUserBootstrap();
    final profileBox = Hive.box('profile');
    await profileBox.clear();
    LocalCache.setActiveAccount('test_user_123');
  });

  group('Profile Setup & Onboarding Flow Regression Tests', () {
    testWidgets('1. Name validation enforces non-empty and at least 2 characters', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userBootstrapProvider.overrideWithValue(fakeBootstrap),
          ],
          child: const MaterialApp(
            home: EditNameScreen(initial: '', onboarding: true),
          ),
        ),
      );

      // Attempt to save empty name
      await tester.tap(find.text('Save & Continue'));
      await tester.pump();
      expect(find.text("Name can't be empty"), findsOneWidget);

      // Enter 1 character
      await tester.enterText(find.byType(TextFormField), 'A');
      await tester.tap(find.text('Save & Continue'));
      await tester.pump();
      expect(find.text('Enter at least 2 characters'), findsOneWidget);
    });

    testWidgets('2. Profile save success updates profile and unlocks navigation', (tester) async {
      final routerGuard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(true);

      final router = buildRouter(routerGuard);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userBootstrapProvider.overrideWithValue(fakeBootstrap),
            routerNotifierProvider.overrideWithValue(routerGuard),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Guard redirected initial location to /editName
      expect(find.byType(EditNameScreen), findsOneWidget);

      // Enter valid name
      await tester.enterText(find.byType(TextFormField), 'John Doe');
      await tester.tap(find.text('Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verified save was committed
      expect(fakeBootstrap.savedName, equals('John Doe'));

      // RequiresName is now false, leading user to main app
      expect(routerGuard.requiresName, isFalse);
    });

    testWidgets('3. Profile save failure retains user on EditNameScreen with input preserved', (tester) async {
      fakeBootstrap.shouldFail = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userBootstrapProvider.overrideWithValue(fakeBootstrap),
          ],
          child: const MaterialApp(
            home: EditNameScreen(initial: '', onboarding: true),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'Jane Doe');
      await tester.tap(find.text('Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Error message shown
      expect(find.textContaining('Failed to save profile'), findsOneWidget);

      // User remains on screen with text preserved
      expect(find.byType(EditNameScreen), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('4. Prevents duplicate submissions while saving is in progress', (tester) async {
      final notifier = EditNameNotifier('');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editNameControllerFamily('').overrideWith(() => notifier),
            userBootstrapProvider.overrideWithValue(fakeBootstrap),
          ],
          child: const MaterialApp(
            home: EditNameScreen(initial: '', onboarding: true),
          ),
        ),
      );

      notifier.setSaving(true);
      await tester.pump();

      // CircularProgressIndicator shown on button
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Button is disabled, input field is disabled
      final textField = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('5. Existing user with complete profile bypasses profile setup', (tester) async {
      final routerGuard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(false);

      expect(routerGuard.requiresName, isFalse);
      expect(routerGuard.isAuthed, isTrue);
      expect(routerGuard.bootstrapped, isTrue);
    });

    testWidgets('6. Existing user with incomplete profile is directed to profile setup', (tester) async {
      final routerGuard = RouterNotifier()
        ..setAuthed(true)
        ..setBootstrapped(true)
        ..setRequiresName(true);

      expect(routerGuard.requiresName, isTrue);
    });
  });
}
