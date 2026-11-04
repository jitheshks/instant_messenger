import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/core/errors/app_error_mapper.dart';

void main() {
  group('AppErrorMapper Unit Tests', () {
    test(
      'Maps PostgrestException 42501 (RLS violation) to permission error',
      () {
        const err = PostgrestException(
          message:
              'new row violates row-level security policy for table "messages"',
          code: '42501',
        );
        final msg = AppErrorMapper.toUserFriendlyMessage(err);
        expect(
          msg,
          equals('You do not have permission to perform this action.'),
        );
      },
    );

    test(
      'Maps PostgrestException 23505 (unique violation) to already exists message',
      () {
        const err = PostgrestException(
          message:
              'duplicate key value violates unique constraint "user_devices_pkey"',
          code: '23505',
        );
        final msg = AppErrorMapper.toUserFriendlyMessage(err);
        expect(msg, equals('This record already exists.'));
      },
    );

    test('Maps SocketException to network unavailable message', () {
      const err = SocketException('Failed host lookup: db.supabase.co');
      final msg = AppErrorMapper.toUserFriendlyMessage(err);
      expect(
        msg,
        equals(
          'Network connection unavailable. Please check your internet connection.',
        ),
      );
    });

    test('Maps TimeoutException to timeout message', () {
      final err = TimeoutException('Operation timed out after 10000ms');
      final msg = AppErrorMapper.toUserFriendlyMessage(err);
      expect(msg, equals('The connection timed out. Please try again.'));
    });

    test('Never leaks raw SQL syntax or relation/column identifiers', () {
      final err = Exception('SELECT * FROM secret_table WHERE id = 123');
      final msg = AppErrorMapper.toUserFriendlyMessage(err);
      expect(msg, equals('An unexpected error occurred. Please try again.'));
      expect(msg.contains('secret_table'), isFalse);
    });
  });
}
