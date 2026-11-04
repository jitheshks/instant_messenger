import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/features/auth/data/auth_error_mapper.dart';
import 'package:instant_messenger/shared/utils/phone_format.dart';

void main() {
  group('AuthErrorMapper Unit Tests', () {
    test('Maps HTTP 429 and rate limit messages to user-friendly text', () {
      const ex1 = AuthException(
        'over_sms_send_rate_limit: wait 60s',
        statusCode: '429',
      );
      expect(
        AuthErrorMapper.toUserFriendlyMessage(ex1),
        contains('Too many requests'),
      );

      const ex2 = AuthException('rate limit exceeded');
      expect(
        AuthErrorMapper.toUserFriendlyMessage(ex2),
        contains('Too many requests'),
      );
    });

    test('Maps invalid/expired token messages to user-friendly text', () {
      const ex = AuthException(
        'Token has expired or is invalid',
        statusCode: '400',
      );
      expect(
        AuthErrorMapper.toUserFriendlyMessage(ex),
        contains('Invalid or expired verification code'),
      );
    });

    test('Maps invalid phone number messages to user-friendly text', () {
      const ex = AuthException('Invalid phone number format');
      expect(
        AuthErrorMapper.toUserFriendlyMessage(ex),
        contains('Invalid phone number format'),
      );
    });

    test('Maps FormatException to clean message', () {
      const ex = FormatException('Invalid phone format');
      expect(
        AuthErrorMapper.toUserFriendlyMessage(ex),
        equals('Invalid phone format'),
      );
    });
  });

  group('PhoneFormat Centralized Normalization Tests', () {
    test('Sanitizes spaces, hyphens, and brackets from phone strings', () {
      expect(PhoneFormat.sanitize('+91 98765-43210'), equals('+919876543210'));
      expect(PhoneFormat.sanitize('+1 (555) 123-4567'), equals('+15551234567'));
    });

    test('isValidE164: Validates true E.164 formats', () {
      expect(PhoneFormat.isValidE164('+919876543210'), isTrue);
      expect(PhoneFormat.isValidE164('+15551234567'), isTrue);
      expect(PhoneFormat.isValidE164('+447911123456'), isTrue);
    });

    test(
      'isValidE164: Rejects numbers lacking leading plus or wrong length',
      () {
        expect(PhoneFormat.isValidE164('9876543210'), isFalse);
        expect(PhoneFormat.isValidE164('+0123456789'), isFalse);
        expect(PhoneFormat.isValidE164('+123'), isFalse);
        expect(PhoneFormat.isValidE164(''), isFalse);
      },
    );
  });
}
