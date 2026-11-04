import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/features/auth/domain/models/otp_session.dart';
import 'package:instant_messenger/shared/utils/phone_format.dart';
import 'auth_error_mapper.dart';
import 'auth_service.dart';

/// Supabase implementation of [AuthService] using Phone SMS OTP.
///
/// Handles SMS delivery requests, OTP token verification, session tracking,
/// and user-friendly error translations for Supabase Auth exceptions.
class SupabaseAuthService implements AuthService {
  final SupabaseClient? _injectedClient;

  SupabaseAuthService([this._injectedClient]);

  /// Resolves the active [SupabaseClient], preferring an injected client (e.g. for testing)
  /// or falling back to the singleton [Supabase.instance.client].
  SupabaseClient get client {
    if (_injectedClient != null) {
      return _injectedClient;
    }
    return Supabase.instance.client;
  }

  SupabaseClient? get safeClient {
    if (_injectedClient != null) {
      return _injectedClient;
    }
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Currently authenticated user, or null if not signed in.
  User? get currentUser => safeClient?.auth.currentUser;

  /// Currently authenticated user UUID string, or null.
  @override
  String? get currentUserId => safeClient?.auth.currentUser?.id;

  /// Currently authenticated user's verified phone number, or null.
  String? get currentPhone => safeClient?.auth.currentUser?.phone;

  /// Whether a valid session exists.
  bool get isAuthenticated => safeClient?.auth.currentSession != null;

  @override
  Stream<bool> authStateChanges() {
    final c = safeClient;
    if (c == null) return const Stream.empty();
    return c.auth.onAuthStateChange.map((data) => data.session != null);
  }

  @override
  Future<OtpSession> startVerification({
    required String e164,
    int? forceResendToken,
  }) async {
    final cleaned = PhoneFormat.sanitize(e164);
    if (!PhoneFormat.isValidE164(cleaned)) {
      throw const FormatException(
        'Invalid phone number format. Please include country dial code (e.g. +91 for India).',
      );
    }

    try {
      debugPrint('[SupabaseAuthService] Requesting SMS OTP for $cleaned');
      await client.auth.signInWithOtp(phone: cleaned, shouldCreateUser: true);

      return OtpSession(
        verificationId: cleaned,
        e164: cleaned,
        resendToken: forceResendToken,
      );
    } on AuthException catch (e) {
      debugPrint(
        '[SupabaseAuthService] AuthException on signInWithOtp: ${e.message} (status: ${e.statusCode})',
      );
      throw AuthException(AuthErrorMapper.toUserFriendlyMessage(e));
    } catch (e) {
      debugPrint('[SupabaseAuthService] Unexpected error on signInWithOtp: $e');
      rethrow;
    }
  }

  @override
  Future<void> verifyCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final code = smsCode.trim();
    if (code.isEmpty) {
      throw const FormatException('Verification code cannot be empty.');
    }

    try {
      debugPrint('[SupabaseAuthService] Verifying SMS OTP for $verificationId');
      final response = await client.auth.verifyOTP(
        phone: verificationId,
        token: code,
        type: OtpType.sms,
      );

      if (response.user == null) {
        throw const AuthException(
          'Verification failed: no user returned from server.',
        );
      }

      debugPrint(
        '[SupabaseAuthService] OTP verified successfully for user: ${response.user?.id}',
      );
    } on AuthException catch (e) {
      debugPrint(
        '[SupabaseAuthService] AuthException on verifyOTP: ${e.message} (status: ${e.statusCode})',
      );
      throw AuthException(AuthErrorMapper.toUserFriendlyMessage(e));
    } catch (e) {
      debugPrint('[SupabaseAuthService] Unexpected error on verifyOTP: $e');
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      debugPrint('[SupabaseAuthService] Signing out...');
      await client.auth.signOut();
    } on AuthException catch (e) {
      debugPrint(
        '[SupabaseAuthService] AuthException on signOut: ${e.message}',
      );
      throw AuthException(AuthErrorMapper.toUserFriendlyMessage(e));
    }
  }
}
