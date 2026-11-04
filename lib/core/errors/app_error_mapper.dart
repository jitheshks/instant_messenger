import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:instant_messenger/features/auth/data/auth_error_mapper.dart';

/// Centralized application-wide error mapper.
///
/// Translates low-level runtime exceptions (Supabase PostgrestException, AuthException,
/// SocketException, TimeoutException) into user-friendly, safe UI messages.
///
/// Ensures raw SQL syntax, internal column names, table names, and stack traces
/// are never leaked to end users.
class AppErrorMapper {
  /// Converts any caught exception into a safe, human-readable user message.
  static String toUserFriendlyMessage(Object error) {
    if (error is AuthException) {
      return AuthErrorMapper.toUserFriendlyMessage(error);
    }

    if (error is PostgrestException) {
      return _mapPostgrestException(error);
    }

    if (error is SocketException) {
      return 'Network connection unavailable. Please check your internet connection.';
    }

    if (error is TimeoutException) {
      return 'The connection timed out. Please try again.';
    }

    if (error is HttpException) {
      return 'Unable to reach the server. Please try again later.';
    }

    if (error is FormatException) {
      return error.message.isNotEmpty
          ? error.message
          : 'Invalid data format received.';
    }

    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      final msg = raw.substring('Exception: '.length).trim();
      // Only return clean strings that do not contain raw SQL or code identifiers
      if (!msg.contains('SELECT') &&
          !msg.contains('INSERT') &&
          !msg.contains('UPDATE') &&
          !msg.contains('DELETE') &&
          !msg.contains('relation "') &&
          !msg.contains('column "')) {
        return msg;
      }
    }

    return 'An unexpected error occurred. Please try again.';
  }

  static String _mapPostgrestException(PostgrestException e) {
    final code = e.code?.trim() ?? '';
    final msg = e.message.toLowerCase();

    // PostgreSQL Error Code 42501: insufficient_privilege / RLS violation
    if (code == '42501' ||
        msg.contains('permission denied') ||
        msg.contains('violates row-level security')) {
      return 'You do not have permission to perform this action.';
    }

    // PostgreSQL Error Code 23505: unique_violation
    if (code == '23505' ||
        msg.contains('already exists') ||
        msg.contains('unique constraint')) {
      return 'This record already exists.';
    }

    // PostgreSQL Error Code 23503: foreign_key_violation
    if (code == '23503') {
      return 'The requested resource is no longer available.';
    }

    // PostgreSQL Error Code 22023: invalid_parameter_value
    if (code == '22023' ||
        msg.contains('invalid argument') ||
        msg.contains('invalid parameter')) {
      return 'Invalid request parameter.';
    }

    // PostgreSQL Error Code P0001: raise_exception (Custom PL/pgSQL app errors)
    if (code == 'P0001') {
      if (msg.contains('rate limit')) {
        return 'Rate limit reached. Please wait a moment before trying again.';
      }
      if (msg.contains('unauthorized')) {
        return 'You are not authorized to perform this operation.';
      }
      // Return cleaned message if safe
      return e.message;
    }

    // Rate limiting HTTP status 429
    final status = int.tryParse(e.code ?? '') ?? 0;
    if (status == 429 || msg.contains('too many requests')) {
      return 'Too many requests. Please wait a moment before trying again.';
    }

    // Gateway / timeout errors
    if (status == 504 || msg.contains('timeout')) {
      return 'The server took too long to respond. Please try again.';
    }

    if (status >= 500) {
      return 'Server is temporarily unavailable. Please try again shortly.';
    }

    return 'Unable to complete the request. Please try again.';
  }
}
