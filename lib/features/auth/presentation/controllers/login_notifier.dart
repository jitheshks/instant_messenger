import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/app/router/router_providers.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/settings/presentation/providers/settings_providers.dart';
import 'package:instant_messenger/features/auth/domain/models/otp_session.dart';
import 'package:instant_messenger/features/auth/data/auth_error_mapper.dart';
import 'package:instant_messenger/core/persistence/local_storage.dart';
import 'package:instant_messenger/core/utils/permission_service.dart';
import 'package:instant_messenger/features/profile/data/user_bootstrap.dart';
import 'package:instant_messenger/shared/utils/phone_format.dart';

@immutable
class LoginState {
  final String countryName;
  final String countryCode;
  final String dialCode;
  final String flagEmoji;
  final String phone;
  final String otpCode;
  final bool loading;
  final String? errorMessage;
  final OtpSession? otp;
  final int secondsLeft;

  const LoginState({
    this.countryName = 'India',
    this.countryCode = 'IN',
    this.dialCode = '+91',
    this.flagEmoji = '🇮🇳',
    this.phone = '',
    this.otpCode = '',
    this.loading = false,
    this.errorMessage,
    this.otp,
    this.secondsLeft = 0,
  });

  bool get canResend => secondsLeft == 0;
  String get fullE164 => '$dialCode$phone';

  LoginState copyWith({
    String? countryName,
    String? countryCode,
    String? dialCode,
    String? flagEmoji,
    String? phone,
    String? otpCode,
    bool? loading,
    String? errorMessage,
    OtpSession? otp,
    int? secondsLeft,
  }) {
    return LoginState(
      countryName: countryName ?? this.countryName,
      countryCode: countryCode ?? this.countryCode,
      dialCode: dialCode ?? this.dialCode,
      flagEmoji: flagEmoji ?? this.flagEmoji,
      phone: phone ?? this.phone,
      otpCode: otpCode ?? this.otpCode,
      loading: loading ?? this.loading,
      errorMessage: errorMessage,
      otp: otp ?? this.otp,
      secondsLeft: secondsLeft ?? this.secondsLeft,
    );
  }
}

class LoginNotifier extends Notifier<LoginState> {
  final _bootstrap = UserBootstrap();
  Timer? _timer;
  static const kResendCooldownSec = 60;

  @override
  LoginState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return const LoginState();
  }

  String? get countryName => state.countryName;
  String? get dialCode => state.dialCode;
  String get countryCode => state.countryCode;
  String? get flagEmoji => state.flagEmoji;
  String get phone => state.phone;
  bool get loading => state.loading;
  String? get errorMessage => state.errorMessage;
  OtpSession? get otp => state.otp;
  int get secondsLeft => state.secondsLeft;
  bool get canResend => state.canResend;
  String get otpCode => state.otpCode;
  String get fullE164 => state.fullE164;

  void onCountryPicked({
    required String name,
    required String countryCode,
    required String dialCode,
    required String flagEmoji,
  }) {
    state = state.copyWith(
      countryName: name,
      countryCode: countryCode,
      dialCode: dialCode,
      flagEmoji: flagEmoji,
    );
  }

  void onPhoneChanged(String v) {
    state = state.copyWith(phone: PhoneFormat.sanitize(v));
  }

  void onOtpChanged(String v) {
    state = state.copyWith(otpCode: v.trim());
  }

  Future<bool> sendVerificationCode() async {
    final local = PhoneFormat.sanitize(state.phone);
    if (local.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter phone number');
      return false;
    }
    final e164 = state.fullE164;
    if (!PhoneFormat.isValidE164(e164)) {
      state = state.copyWith(errorMessage: 'Invalid phone format');
      return false;
    }

    state = state.copyWith(loading: true, errorMessage: null);

    try {
      final auth = ref.read(authServiceProvider);
      final session = await auth.startVerification(e164: e164);
      state = state.copyWith(otp: session);
      _startResendTimer(kResendCooldownSec);
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: AuthErrorMapper.toUserFriendlyMessage(e),
      );
      return false;
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<bool> resendVerificationCode() async {
    if (!state.canResend || state.otp == null || state.loading) return false;
    final old = state.otp!;

    state = state.copyWith(loading: true, errorMessage: null);

    try {
      final auth = ref.read(authServiceProvider);
      final session = await auth.startVerification(
        e164: old.e164,
        forceResendToken: old.resendToken,
      );
      state = state.copyWith(otp: session);
      _startResendTimer(kResendCooldownSec);
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: AuthErrorMapper.toUserFriendlyMessage(e),
      );
      return false;
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<NextRoute?> verifyOtpCode([String? codeToVerify]) async {
    final code = (codeToVerify ?? state.otpCode).trim();
    if (state.otp == null) {
      state = state.copyWith(
        errorMessage: 'Session expired. Please request a new code.',
      );
      return null;
    }
    if (code.length < 4) {
      state = state.copyWith(errorMessage: 'Enter the code');
      return null;
    }

    state = state.copyWith(loading: true, errorMessage: null);

    try {
      final auth = ref.read(authServiceProvider);
      await auth.verifyCode(
        verificationId: state.otp!.verificationId,
        smsCode: code,
      );

      final next = await _bootstrap.bootstrap();
      final router = ref.read(routerNotifierProvider);
      router.setRequiresName(next == NextRoute.editName);
      router.setAuthed(true);
      router.setBootstrapped(true);
      return next;
    } catch (e) {
      state = state.copyWith(
        errorMessage: AuthErrorMapper.toUserFriendlyMessage(e),
      );
      return null;
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> onNext(BuildContext context) async {
    final success = await sendVerificationCode();
    if (!context.mounted) return;
    if (success) {
      context.go('/otp');
    } else if (state.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    }
  }

  Future<void> resendCode(BuildContext context) async {
    final success = await resendVerificationCode();
    if (!context.mounted) return;
    if (!success && state.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    }
  }

  Future<void> submitCode(BuildContext context, String code) async {
    final next = await verifyOtpCode(code);
    if (!context.mounted) return;

    if (next != null) {
      ref.read(settingsControllerProvider.notifier).start();

      final askedOnce = await LocalStorage().getPermissionsAsked();
      if (!askedOnce) {
        await PermissionService.requestFirstLoginPermissions(
          includeMicrophone: true,
          includeLocation: true,
        );
        await LocalStorage().setPermissionsAsked(true);
      }

      if (!context.mounted) return;
      switch (next) {
        case NextRoute.editName:
          context.go('/editName');
          break;
        case NextRoute.profile:
          context.go('/profile');
          break;
        case NextRoute.chats:
          context.go('/chats');
          break;
      }
    } else if (state.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    }
  }

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    state = state.copyWith(secondsLeft: seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (state.secondsLeft <= 1) {
        t.cancel();
        state = state.copyWith(secondsLeft: 0);
      } else {
        state = state.copyWith(secondsLeft: state.secondsLeft - 1);
      }
    });
  }

  Future<void> submitOtp(BuildContext context) =>
      submitCode(context, state.otpCode);
}
