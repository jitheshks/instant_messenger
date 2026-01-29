import '../models/otp_session.dart';

abstract class AuthService {
  /// Begin phone verification, return [OtpSession] when code is sent
   Future<OtpSession> startVerification({required String e164, int? forceResendToken});


  /// Complete sign-in with code
    Future<void> verifyCode({required String verificationId, required String smsCode});

  /// Observe auth state changes (signed in / signed out)
  Stream<bool> authStateChanges();

  Future<void> signOut();
}
