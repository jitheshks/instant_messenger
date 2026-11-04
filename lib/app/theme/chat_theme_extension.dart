import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Strongly-typed theme extension for WhatsApp-style chat elements.
@immutable
class ChatThemeExtension extends ThemeExtension<ChatThemeExtension> {
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color textSent;
  final Color textReceived;
  final Color timestampSent;
  final Color timestampReceived;
  final Color tickRead;
  final Color tickDelivered;
  final Color chatBackground;
  final Color inputBackground;
  final Color inputHint;

  const ChatThemeExtension({
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.textSent,
    required this.textReceived,
    required this.timestampSent,
    required this.timestampReceived,
    required this.tickRead,
    required this.tickDelivered,
    required this.chatBackground,
    required this.inputBackground,
    required this.inputHint,
  });

  /// Light palette with mathematically verified WCAG AA contrast tokens.
  static const light = ChatThemeExtension(
    bubbleSent: AppColors.lightBubbleSent,
    bubbleReceived: AppColors.lightBubbleReceived,
    textSent: AppColors.lightTextPrimary,
    textReceived: AppColors.lightTextPrimary,
    timestampSent: AppColors.lightTextSecondary,
    timestampReceived: AppColors.lightTextSecondary,
    tickRead: AppColors.lightTickRead,
    tickDelivered: AppColors.lightTickDelivered,
    chatBackground: AppColors.lightScaffold,
    inputBackground: AppColors.lightInputBackground,
    inputHint: AppColors.lightInputHint,
  );

  /// Dark palette with mathematically verified WCAG AA contrast tokens.
  static const dark = ChatThemeExtension(
    bubbleSent: AppColors.darkBubbleSent,
    bubbleReceived: AppColors.darkBubbleReceived,
    textSent: AppColors.darkTextPrimary,
    textReceived: AppColors.darkTextPrimary,
    timestampSent: AppColors.darkTimestampSent,
    timestampReceived: AppColors.darkTextSecondary,
    tickRead: AppColors.darkTickRead,
    tickDelivered: AppColors.darkTickDelivered,
    chatBackground: AppColors.darkScaffold,
    inputBackground: AppColors.darkInputBackground,
    inputHint: AppColors.darkInputHint,
  );

  /// Convenient accessor that falls back to dark or light defaults based on brightness.
  static ChatThemeExtension of(BuildContext context) {
    return Theme.of(context).extension<ChatThemeExtension>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ChatThemeExtension.dark
            : ChatThemeExtension.light);
  }

  @override
  ChatThemeExtension copyWith({
    Color? bubbleSent,
    Color? bubbleReceived,
    Color? textSent,
    Color? textReceived,
    Color? timestampSent,
    Color? timestampReceived,
    Color? tickRead,
    Color? tickDelivered,
    Color? chatBackground,
    Color? inputBackground,
    Color? inputHint,
  }) {
    return ChatThemeExtension(
      bubbleSent: bubbleSent ?? this.bubbleSent,
      bubbleReceived: bubbleReceived ?? this.bubbleReceived,
      textSent: textSent ?? this.textSent,
      textReceived: textReceived ?? this.textReceived,
      timestampSent: timestampSent ?? this.timestampSent,
      timestampReceived: timestampReceived ?? this.timestampReceived,
      tickRead: tickRead ?? this.tickRead,
      tickDelivered: tickDelivered ?? this.tickDelivered,
      chatBackground: chatBackground ?? this.chatBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      inputHint: inputHint ?? this.inputHint,
    );
  }

  @override
  ThemeExtension<ChatThemeExtension> lerp(
    covariant ThemeExtension<ChatThemeExtension>? other,
    double t,
  ) {
    if (other is! ChatThemeExtension) return this;
    return ChatThemeExtension(
      bubbleSent: Color.lerp(bubbleSent, other.bubbleSent, t)!,
      bubbleReceived: Color.lerp(bubbleReceived, other.bubbleReceived, t)!,
      textSent: Color.lerp(textSent, other.textSent, t)!,
      textReceived: Color.lerp(textReceived, other.textReceived, t)!,
      timestampSent: Color.lerp(timestampSent, other.timestampSent, t)!,
      timestampReceived: Color.lerp(
        timestampReceived,
        other.timestampReceived,
        t,
      )!,
      tickRead: Color.lerp(tickRead, other.tickRead, t)!,
      tickDelivered: Color.lerp(tickDelivered, other.tickDelivered, t)!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputHint: Color.lerp(inputHint, other.inputHint, t)!,
    );
  }
}
