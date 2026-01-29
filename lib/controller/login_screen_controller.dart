import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:instant_messenger/controller/settings_controller.dart';
import 'package:instant_messenger/services/local_storage.dart';
import 'package:instant_messenger/services/permission_service.dart';
import 'package:instant_messenger/services/user_bootstrap.dart';
import 'package:provider/provider.dart';
import '../models/otp_session.dart';
import '../services/auth_service.dart';
import '../app_router/router_notifier.dart';

class LoginController extends ChangeNotifier {
  LoginController(this._auth, this._guard)
    : _countryName = 'India',
      _countryCode = 'IN',
      _dialCode = '+91',
      _flagEmoji = '🇮🇳';

  final AuthService _auth;
  final RouterNotifier _guard;
  final _bootstrap = UserBootstrap();

  // OTP entry
  String _otpCode = '';
  String get otpCode => _otpCode;

  // Country UI state
  String? _countryName;
  String? _dialCode;
  String _countryCode;
  String _flagEmoji;

  // Phone/flow state
  String _phone = '';
  bool _loading = false;

  // OTP state
  OtpSession? _otp;
  int _secondsLeft = 0;
  Timer? _timer;

  // Constants
  static const kResendCooldownSec = 60;
  static final _e164 = RegExp(r'^\+[1-9]\d{1,14}$');

  // Getters
  String? get countryName => _countryName;
  String? get dialCode => _dialCode;
  String get countryCode => _countryCode;
  String? get flagEmoji => _flagEmoji;
  String get phone => _phone;
  bool get loading => _loading;
  OtpSession? get otp => _otp;
  int get secondsLeft => _secondsLeft;
  bool get canResend => _secondsLeft == 0;

  // UI actions
  void onCountryPicked({
    required String name,
    required String countryCode,
    required String dialCode,
    required String flagEmoji,
  }) {
    _countryName = name;
    _countryCode = countryCode;
    _dialCode = dialCode;
    _flagEmoji = flagEmoji;
    notifyListeners();
  }

  void onPhoneChanged(String v) {
    _phone = v.replaceAll(RegExp(r'\s+'), '');
    notifyListeners();
  }

  String get fullE164 => '${_dialCode ?? ''}$_phone';

  // Start verification from login screen
  Future<void> onNext(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final local = _phone.replaceAll(RegExp(r'\s+'), '');
    if (local.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter phone number')),
      );
      return;
    }
    final e164 = fullE164;
    final ok = _e164.hasMatch(e164);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Invalid phone format')),
      );
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final session = await _auth.startVerification(e164: e164);
      _otp = session;
      _startResendTimer(kResendCooldownSec);
      notifyListeners();

      if (context.mounted) {
        context.go('/otp');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to send code: $e')),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Resend code
  Future<void> resendCode(BuildContext context) async {
    if (!canResend || _otp == null || _loading) return;
    final old = _otp!;
    try {
      _loading = true;
      notifyListeners();
      final session = await _auth.startVerification(
        e164: old.e164,
        forceResendToken: old.resendToken,
      );
      _otp = session;
      _startResendTimer(kResendCooldownSec);
      notifyListeners();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Resend failed: $e')));
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Verify entered code and bootstrap profile
  // Verify entered code and bootstrap profile
  // Verify entered code and bootstrap profile
  Future<void> submitCode(BuildContext context, String code) async {
    if (_otp == null) return;
    if (code.trim().length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter the code')));
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      await _auth.verifyCode(
        verificationId: _otp!.verificationId,
        smsCode: code.trim(),
      );

      // ✅ Start Settings stream immediately after successful login
      final sc = context.read<SettingsController>();
      sc.start(); // idempotent — safe to call multiple times

      // ✅ 1) Decide next route based on Firestore profile
      final next = await _bootstrap.bootstrap();

      // ✅ 2) Set router gates BEFORE navigating
      _guard.setAuthed(true);
      

      // ✅ 3) One-time permission bundle right after login
final askedOnce = await LocalStorage().getPermissionsAsked();
if (!askedOnce) {
  await PermissionService.requestFirstLoginPermissions(
    includeMicrophone: true,
    includeLocation: true,
  );
  await LocalStorage().setPermissionsAsked(true);
}


      // ✅ 4) Navigate
      if (context.mounted) {
        switch (next) {
          case NextRoute.editName:
            context.go('/editName', extra: '');
            break;
          case NextRoute.profile:
            context.go('/profile');
            break;
          case NextRoute.chats:
            context.go('/chats');
            break;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid code')));
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    _secondsLeft = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        _secondsLeft = 0;
        t.cancel();
      } else {
        _secondsLeft -= 1;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void onOtpChanged(String v) {
    _otpCode = v.trim();
  }

  Future<void> submitOtp(BuildContext context) => submitCode(context, _otpCode);
}
