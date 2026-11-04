import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController State & Persistence Tests', () {
    test(
      'TC-THM-01: Default theme mode is system when SharedPreferences is empty',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = ThemeController(prefs);

        expect(controller.themeMode, equals(AppThemeMode.system));
        expect(controller.flutterThemeMode, equals(ThemeMode.system));
      },
    );

    test(
      'TC-THM-01: Changing theme mode persists to SharedPreferences and notifies listeners',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = ThemeController(prefs);

        int notifyCount = 0;
        controller.addListener(() {
          notifyCount++;
        });

        await controller.setThemeMode(AppThemeMode.dark);

        expect(controller.themeMode, equals(AppThemeMode.dark));
        expect(controller.flutterThemeMode, equals(ThemeMode.dark));
        expect(notifyCount, equals(1));
        expect(prefs.getString(ThemeController.prefKey), equals('dark'));

        // Re-instantiating controller loads saved dark mode
        final reloaded = ThemeController(prefs);
        expect(reloaded.themeMode, equals(AppThemeMode.dark));
      },
    );

    test('TC-THM-01: Setting same mode is a no-op (does not notify)', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setThemeMode(AppThemeMode.light);

      expect(notifyCount, equals(0));
    });
  });
}
