// lib/theme/theme.dart
import 'package:flutter/material.dart';

extension ColorShade on Color {
  Color darken([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final h = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return h.toColor();
  }
}

ThemeData baseTheme({
  required Color seed,
  required Brightness brightness,
  InputDecorationTheme? inputDecorationTheme,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    inputDecorationTheme: inputDecorationTheme ??
        const InputDecorationTheme(
          isDense: true,
          border: UnderlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent, // remove M3 tint overlay
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
      ),
    ),
  );
}

({ThemeData light, ThemeData dark}) themedPair(Color seed) {
  final baseLight = baseTheme(seed: seed, brightness: Brightness.light);
  final baseDark  = baseTheme(seed: seed, brightness: Brightness.dark);

  final sL = baseLight.colorScheme;
  final sD = baseDark.colorScheme;

  // Light NavigationBar theme: unified surface background, no tint
  final lightNav = NavigationBarThemeData(
    backgroundColor: sL.surface,
    surfaceTintColor: Colors.transparent,
    indicatorColor: sL.primary.withValues(alpha: 0.12),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? sL.primary.darken(0.25) : Colors.black);
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(color: selected ? sL.primary.darken(0.25) : Colors.black);
    }),
  );

  // Dark NavigationBar theme: unified surface background, no tint
  final darkNav = NavigationBarThemeData(
    backgroundColor: sD.surface,
    surfaceTintColor: Colors.transparent,
    indicatorColor: sD.onSurface.withValues(alpha: 0.10),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(
        color: selected ? sD.onSurface.withValues(alpha: 0.90)
                        : sD.onSurface.withValues(alpha: 0.70),
      );
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        color: selected ? sD.onSurface.withValues(alpha: 0.90)
                        : sD.onSurface.withValues(alpha: 0.70),
      );
    }),
  );

  // Global PopupMenuTheme for TabMenu and any menus
  final light = baseLight.copyWith(
    navigationBarTheme: lightNav,
    popupMenuTheme: PopupMenuThemeData(
      color: sL.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );

  final dark = baseDark.copyWith(
    navigationBarTheme: darkNav,
    popupMenuTheme: PopupMenuThemeData(
      color: sD.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );

  return (light: light, dark: dark);
}
