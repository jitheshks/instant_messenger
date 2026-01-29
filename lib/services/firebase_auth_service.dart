import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/otp_session.dart';
import 'auth_service.dart';

class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth;
  FirebaseAuthService(this._auth);

  @override
  Stream<bool> authStateChanges() => _auth.authStateChanges().map((u) => u != null);

  @override
  Future<OtpSession> startVerification({required String e164, int? forceResendToken}) async {
    final c = Completer<OtpSession>();
    await _auth.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: forceResendToken,                  // key for resend [web:416]
      verificationCompleted: (cred) async {
        // Optional: auto sign-in; controller can also listen to authStateChanges
        await _auth.signInWithCredential(cred);
      },
      verificationFailed: (e) {
        if (!c.isCompleted) c.completeError(e);
      },
      codeSent: (verificationId, resendToken) {
        if (!c.isCompleted) {
          c.complete(OtpSession(
            verificationId: verificationId,
            resendToken: resendToken,
            e164: e164,
          ));
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        // Keep verificationId if needed; not used here
      },
    );
    return c.future;
  }

  @override
  Future<void> verifyCode({required String verificationId, required String smsCode}) async {
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId, smsCode: smsCode,
    );
    await _auth.signInWithCredential(cred);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
