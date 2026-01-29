class OtpSession {
  final String verificationId;
  final int? resendToken;
  final String e164; // for display/resend
  const OtpSession({
    required this.verificationId,
    required this.e164,
    this.resendToken,
  });

  OtpSession copyWith({String? verificationId, int? resendToken}) => OtpSession(
    verificationId: verificationId ?? this.verificationId,
    e164: e164,
    resendToken: resendToken ?? this.resendToken,
  );
}
