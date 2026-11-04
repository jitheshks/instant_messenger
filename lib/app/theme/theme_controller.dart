import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available application theme modes.
enum AppThemeMode { system, light, dark }

/// Centralized state manager for application theme modes.
/// Supports Light, Dark, and System-Default modes with persistent preferences.
class ThemeController extends ChangeNotifier {
  static const String prefKey = 'app_theme_mode';

  final SharedPreferences _prefs;
  AppThemeMode _themeMode;

  ThemeController(this._prefs) : _themeMode = _loadFromPrefs(_prefs);

  /// Active application theme mode.
  AppThemeMode get themeMode => _themeMode;

  /// Translates [AppThemeMode] to Flutter's native [ThemeMode].
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Evaluates whether the currently displayed theme is effectively dark.
  bool isDarkMode(BuildContext context) {
    if (_themeMode == AppThemeMode.light) return false;
    if (_themeMode == AppThemeMode.dark) return true;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  /// Sets and persists a new theme mode.
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs.setString(prefKey, mode.name);
    notifyListeners();
  }

  /// Toggles between light and dark (bypassing system).
  Future<void> toggleTheme(BuildContext context) async {
    final currentIsDark = isDarkMode(context);
    await setThemeMode(currentIsDark ? AppThemeMode.light : AppThemeMode.dark);
  }

  static AppThemeMode _loadFromPrefs(SharedPreferences prefs) {
    final saved = prefs.getString(prefKey);
    if (saved == null) return AppThemeMode.system;

    return AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.system,
    );
  }
}
