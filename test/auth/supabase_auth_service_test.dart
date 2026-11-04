import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/features/auth/data/supabase_auth_service.dart';

void main() {
  group('SupabaseAuthService Phone Authentication Tests', () {
    test('Client injection and fallback getter', () {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final service = SupabaseAuthService(mockClient);
      expect(service.client, equals(mockClient));
      expect(service.isAuthenticated, isFalse);
      expect(service.currentUser, isNull);
      expect(service.currentUserId, isNull);
    });

    test(
      'startVerification: Rejects numbers lacking leading plus or country code',
      () async {
        final mockClient = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
        );
        final service = SupabaseAuthService(mockClient);

        expect(
          () => service.startVerification(e164: '9876543210'),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => service.startVerification(e164: '123'),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => service.startVerification(e164: ''),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'startVerification: Sanitizes formatted numbers and requests OTP successfully',
      () async {
        String? requestedPhone;

        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/auth/v1/otp')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            requestedPhone = body['phone'] as String?;
            return http.Response(
              jsonEncode({'message': 'OTP sent'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = SupabaseAuthService(client);

        // Input with spaces and hyphens
        final session = await service.startVerification(
          e164: '+91 98765-43210',
          forceResendToken: 42,
        );

        expect(requestedPhone, equals('+919876543210'));
        expect(session.verificationId, equals('+919876543210'));
        expect(session.e164, equals('+919876543210'));
        expect(session.resendToken, equals(42));
      },
    );

    test(
      'startVerification: Maps HTTP 429 rate limit to user-friendly AuthException',
      () async {
        final mockHttp = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 429,
              'message':
                  'over_sms_send_rate_limit: For security purposes, you can only request this after 60 seconds.',
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = SupabaseAuthService(client);

        expect(
          () => service.startVerification(e164: '+919876543210'),
          throwsA(
            predicate(
              (e) =>
                  e is AuthException &&
                  e.message.contains('Too many requests') &&
                  e.message.contains('wait a moment'),
            ),
          ),
        );
      },
    );

    test('verifyCode: Rejects empty or whitespace-only code', () async {
      final mockClient = SupabaseClient('https://mock.supabase.co', 'mock-key');
      final service = SupabaseAuthService(mockClient);

      expect(
        () => service.verifyCode(verificationId: '+919876543210', smsCode: ''),
        throwsA(isA<FormatException>()),
      );

      expect(
        () =>
            service.verifyCode(verificationId: '+919876543210', smsCode: '   '),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'verifyCode: Completes verification on valid token and user session',
      () async {
        final mockHttp = MockClient((request) async {
          if (request.url.path.contains('/auth/v1/verify')) {
            return http.Response(
              jsonEncode({
                'access_token': 'fake-jwt-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'fake-refresh-token',
                'user': {
                  'id': 'c9ccc86c-cd42-40bb-8678-d9a30964ce30',
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': '',
                  'phone': '+919876543210',
                  'created_at': DateTime.now().toIso8601String(),
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = SupabaseAuthService(client);

        await expectLater(
          service.verifyCode(
            verificationId: '+919876543210',
            smsCode: '123456',
          ),
          completes,
        );
      },
    );

    test(
      'verifyCode: Maps expired or invalid OTP code to user-friendly message',
      () async {
        final mockHttp = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 400,
              'message': 'Token has expired or is invalid',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = SupabaseClient(
          'https://mock.supabase.co',
          'mock-key',
          httpClient: mockHttp,
        );
        final service = SupabaseAuthService(client);

        expect(
          () => service.verifyCode(
            verificationId: '+919876543210',
            smsCode: '999999',
          ),
          throwsA(
            predicate(
              (e) =>
                  e is AuthException &&
                  e.message.contains('Invalid or expired verification code'),
            ),
          ),
        );
      },
    );

    test('signOut: Executes signOut cleanly via client', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path.contains('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final client = SupabaseClient(
        'https://mock.supabase.co',
        'mock-key',
        httpClient: mockHttp,
      );
      final service = SupabaseAuthService(client);

      await expectLater(service.signOut(), completes);
    });
  });
}
