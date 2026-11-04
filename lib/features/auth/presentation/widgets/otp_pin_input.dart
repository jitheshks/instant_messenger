import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pinput/pinput.dart';

/// Reusable OTP PIN input widget built on top of [Pinput] with built-in Material compatibility.
///
/// Encapsulates the Material and Localization boundaries required by modern Pinput releases,
/// providing seamless integration with the application's Flutter Material design system, theme,
/// and layout constraints.
class OtpPinInput extends StatelessWidget {
  /// Number of PIN digits/cells to display. Defaults to 6.
  final int length;

  /// Callback triggered when any digit changes.
  final ValueChanged<String>? onChanged;

  /// Callback triggered when all digits are completed.
  final ValueChanged<String>? onCompleted;

  /// Custom theme for standard PIN cells. If omitted, derives from current [Theme].
  final PinTheme? defaultPinTheme;

  /// Custom theme for the active/focused PIN cell.
  final PinTheme? focusedPinTheme;

  /// Custom theme for already submitted PIN cells.
  final PinTheme? submittedPinTheme;

  /// Custom theme when validation error state is active.
  final PinTheme? errorPinTheme;

  /// Optional text editing controller for external control.
  final TextEditingController? controller;

  /// Optional focus node for external focus management.
  final FocusNode? focusNode;

  /// Whether the input is active. Defaults to true.
  final bool enabled;

  /// Whether the input should automatically request focus. Defaults to false.
  final bool autofocus;

  const OtpPinInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.defaultPinTheme,
    this.focusedPinTheme,
    this.submittedPinTheme,
    this.errorPinTheme,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final effectiveDefaultTheme = defaultPinTheme ??
        PinTheme(
          width: 48,
          height: 56,
          textStyle: textTheme.headlineSmall,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
        );

    final effectiveFocusedTheme = focusedPinTheme ??
        effectiveDefaultTheme.copyWith(
          decoration: effectiveDefaultTheme.decoration?.copyWith(
            border: Border.all(color: cs.primary, width: 2),
          ),
        );

    // Bridge standard Flutter Material into modern Pinput requirements
    return Localizations.override(
      context: context,
      delegates: const [
        mui.DefaultMaterialLocalizations.delegate,
      ],
      child: mui.Material(
        type: mui.MaterialType.transparency,
        child: Pinput(
          length: length,
          defaultPinTheme: effectiveDefaultTheme,
          focusedPinTheme: effectiveFocusedTheme,
          submittedPinTheme: submittedPinTheme,
          errorPinTheme: errorPinTheme,
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          onChanged: onChanged,
          onCompleted: onCompleted,
        ),
      ),
    );
  }
}
