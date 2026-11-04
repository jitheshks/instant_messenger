import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/app/theme/chat_theme_extension.dart';

/// Calculates W3C WCAG 2.1 relative luminance:
/// L = 0.2126 * R + 0.7152 * G + 0.0722 * B
double calculateLuminance(Color color) {
  double channelToLinear(int channel255) {
    final c = channel255 / 255.0;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channelToLinear((color.r * 255.0).round().clamp(0, 255));
  final g = channelToLinear((color.g * 255.0).round().clamp(0, 255));
  final b = channelToLinear((color.b * 255.0).round().clamp(0, 255));

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Calculates W3C WCAG 2.1 contrast ratio:
/// (L1 + 0.05) / (L2 + 0.05) where L1 is lighter and L2 is darker.
double calculateContrastRatio(Color foreground, Color background) {
  final l1 = calculateLuminance(foreground);
  final l2 = calculateLuminance(background);

  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);

  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('WCAG 2.1 Contrast Ratio Verification', () {
    test('Light Chat Theme satisfies WCAG AA thresholds', () {
      const ext = ChatThemeExtension.light;

      // Sent bubble text (Normal text >= 4.5:1)
      final sentTextRatio = calculateContrastRatio(
        ext.textSent,
        ext.bubbleSent,
      );
      expect(
        sentTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Sent bubble text ($sentTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Sent bubble timestamp (Normal text >= 4.5:1)
      final sentTimestampRatio = calculateContrastRatio(
        ext.timestampSent,
        ext.bubbleSent,
      );
      expect(
        sentTimestampRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Sent bubble timestamp ($sentTimestampRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Received bubble text (Normal text >= 4.5:1)
      final receivedTextRatio = calculateContrastRatio(
        ext.textReceived,
        ext.bubbleReceived,
      );
      expect(
        receivedTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Received bubble text ($receivedTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Received bubble timestamp (Normal text >= 4.5:1)
      final receivedTimestampRatio = calculateContrastRatio(
        ext.timestampReceived,
        ext.bubbleReceived,
      );
      expect(
        receivedTimestampRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Received bubble timestamp ($receivedTimestampRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Sent bubble read checkmark (UI component >= 3.0:1)
      final readTickRatio = calculateContrastRatio(
        ext.tickRead,
        ext.bubbleSent,
      );
      expect(
        readTickRatio,
        greaterThanOrEqualTo(3.0),
        reason:
            'Read tick ($readTickRatio:1) must meet WCAG AA UI component threshold (>= 3.0:1)',
      );

      // Sent bubble delivered checkmark (UI component >= 3.0:1)
      final deliveredTickRatio = calculateContrastRatio(
        ext.tickDelivered,
        ext.bubbleSent,
      );
      expect(
        deliveredTickRatio,
        greaterThanOrEqualTo(3.0),
        reason:
            'Delivered tick ($deliveredTickRatio:1) must meet WCAG AA UI component threshold (>= 3.0:1)',
      );

      // Input field text on input background (Normal text >= 4.5:1)
      final inputTextRatio = calculateContrastRatio(
        AppColors.lightTextPrimary,
        ext.inputBackground,
      );
      expect(
        inputTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Input text ($inputTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Input field hint on input background (Normal text >= 4.5:1)
      final inputHintRatio = calculateContrastRatio(
        ext.inputHint,
        ext.inputBackground,
      );
      expect(
        inputHintRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Input hint ($inputHintRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );
    });

    test('Dark Chat Theme satisfies WCAG AA thresholds', () {
      const ext = ChatThemeExtension.dark;

      // Dark sent bubble text (Normal text >= 4.5:1)
      final sentTextRatio = calculateContrastRatio(
        ext.textSent,
        ext.bubbleSent,
      );
      expect(
        sentTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark sent text ($sentTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Dark sent bubble timestamp (Normal text >= 4.5:1)
      final sentTimestampRatio = calculateContrastRatio(
        ext.timestampSent,
        ext.bubbleSent,
      );
      expect(
        sentTimestampRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark sent timestamp ($sentTimestampRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Dark received bubble text (Normal text >= 4.5:1)
      final receivedTextRatio = calculateContrastRatio(
        ext.textReceived,
        ext.bubbleReceived,
      );
      expect(
        receivedTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark received text ($receivedTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Dark received bubble timestamp (Normal text >= 4.5:1)
      final receivedTimestampRatio = calculateContrastRatio(
        ext.timestampReceived,
        ext.bubbleReceived,
      );
      expect(
        receivedTimestampRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark received timestamp ($receivedTimestampRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Dark sent bubble read checkmark (UI component >= 3.0:1)
      final readTickRatio = calculateContrastRatio(
        ext.tickRead,
        ext.bubbleSent,
      );
      expect(
        readTickRatio,
        greaterThanOrEqualTo(3.0),
        reason:
            'Dark read tick ($readTickRatio:1) must meet WCAG AA UI component threshold (>= 3.0:1)',
      );

      // Dark sent bubble delivered checkmark (UI component >= 3.0:1)
      final deliveredTickRatio = calculateContrastRatio(
        ext.tickDelivered,
        ext.bubbleSent,
      );
      expect(
        deliveredTickRatio,
        greaterThanOrEqualTo(3.0),
        reason:
            'Dark delivered tick ($deliveredTickRatio:1) must meet WCAG AA UI component threshold (>= 3.0:1)',
      );

      // Dark input field text on input background (Normal text >= 4.5:1)
      final inputTextRatio = calculateContrastRatio(
        ext.textSent,
        ext.inputBackground,
      );
      expect(
        inputTextRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark input text ($inputTextRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );

      // Dark input field hint on input background (Normal text >= 4.5:1)
      final inputHintRatio = calculateContrastRatio(
        ext.inputHint,
        ext.inputBackground,
      );
      expect(
        inputHintRatio,
        greaterThanOrEqualTo(4.5),
        reason:
            'Dark input hint ($inputHintRatio:1) must meet WCAG AA normal text threshold (>= 4.5:1)',
      );
    });

    test('App Surface tokens satisfy WCAG AA thresholds in both modes', () {
      // Light surface text
      final lightPrimaryRatio = calculateContrastRatio(
        AppColors.lightTextPrimary,
        AppColors.lightSurface,
      );
      expect(lightPrimaryRatio, greaterThanOrEqualTo(4.5));

      final lightSecondaryRatio = calculateContrastRatio(
        AppColors.lightTextSecondary,
        AppColors.lightSurface,
      );
      expect(lightSecondaryRatio, greaterThanOrEqualTo(4.5));

      final lightErrorRatio = calculateContrastRatio(
        AppColors.error,
        AppColors.lightSurface,
      );
      expect(lightErrorRatio, greaterThanOrEqualTo(4.5));

      // Dark surface text
      final darkPrimaryRatio = calculateContrastRatio(
        AppColors.darkTextPrimary,
        AppColors.darkSurface,
      );
      expect(darkPrimaryRatio, greaterThanOrEqualTo(4.5));

      final darkSecondaryRatio = calculateContrastRatio(
        AppColors.darkTextSecondary,
        AppColors.darkSurface,
      );
      expect(darkSecondaryRatio, greaterThanOrEqualTo(4.5));

      final darkErrorRatio = calculateContrastRatio(
        AppColors.errorDark,
        AppColors.darkSurface,
      );
      expect(darkErrorRatio, greaterThanOrEqualTo(4.5));
    });
  });
}
