import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 & Phase 2 Hardening Regression Tests', () {
    late String migration3Sql;

    setUpAll(() {
      final migrationFile = File('supabase/migrations/20261026000003_rpc_functions_and_triggers.sql');
      expect(migrationFile.existsSync(), isTrue, reason: 'Migration 3 must exist');
      migration3Sql = migrationFile.readAsStringSync();
    });

    group('Task A: Contact Matching RPC Hardening', () {
      test('Validates null and empty inputs before rate limit mutation', () {
        // Must check null/empty before insert into contact_match_rate_limits
        final nullCheckIndex = migration3Sql.indexOf(
          'if p_phone_numbers is null or pg_catalog.array_length(p_phone_numbers, 1) is null then',
        );
        final rateLimitIndex = migration3Sql.indexOf(
          'insert into public.contact_match_rate_limits',
        );

        expect(nullCheckIndex, isNonNegative);
        expect(rateLimitIndex, isNonNegative);
        expect(nullCheckIndex < rateLimitIndex, isTrue,
            reason: 'Null and empty validation must execute prior to rate-limit writes');
      });

      test('Enforces maximum batch size of 200 before rate limit mutation', () {
        final batchCheckIndex = migration3Sql.indexOf(
          'if pg_catalog.array_length(p_phone_numbers, 1) > 200 then',
        );
        final rateLimitIndex = migration3Sql.indexOf(
          'insert into public.contact_match_rate_limits',
        );

        expect(batchCheckIndex, isNonNegative);
        expect(batchCheckIndex < rateLimitIndex, isTrue,
            reason: 'Batch size check must execute prior to rate-limit writes');
        expect(migration3Sql.contains("using errcode = '22023'"), isTrue);
      });

      test('Implements atomic concurrency-safe sliding window rate limiting', () {
        expect(migration3Sql.contains('on conflict (user_id) do update'), isTrue);
        expect(migration3Sql.contains('interval \'15 minutes\''), isTrue);
        expect(migration3Sql.contains('using errcode = \'P0001\''), isTrue);
      });
    });

    group('Task B: Profile Backfill Idempotency & Collision Protection', () {
      test('Guards against unique constraint collision with existing profiles', () {
        expect(
          migration3Sql.contains('not exists ('),
          isTrue,
        );
        expect(
          migration3Sql.contains('select 1 from public.profiles ep'),
          isTrue,
          reason: 'Must check if phone_e164 is already held by an existing profile',
        );
        expect(
          migration3Sql.contains('where ep.phone_e164 = c.clean_phone'),
          isTrue,
        );
      });

      test('Enforces strict E.164 phone normalization in backfill query', () {
        expect(
          migration3Sql.contains(r"'^\+?[1-9]\d{6,14}$'"),
          isTrue,
          reason: 'Backfill must validate and normalize E.164 format (with or without leading +)',
        );
      });

      test('Ensures idempotent rerun without data destruction', () {
        expect(
          migration3Sql.contains('where not exists (select 1 from public.profiles p where p.id = u.id)'),
          isTrue,
          reason: 'Backfill must strictly candidate users without existing profile rows',
        );
        expect(
          migration3Sql.contains('on conflict (id) do nothing;'),
          isTrue,
        );
      });
    });

    group('Task C: Auth Profile Synchronization', () {
      test('Trigger is bound to INSERT and UPDATE OF phone only', () {
        expect(
          migration3Sql.contains('after insert or update of phone on auth.users'),
          isTrue,
          reason: 'Must only trigger on phone changes, ignoring unrelated metadata',
        );
      });

      test('Normalizes E.164 format and handles duplicate phone handover cleanly', () {
        expect(
          migration3Sql.contains(r"new.phone is not null and pg_catalog.btrim(new.phone) ~ '^\+?[1-9]\d{6,14}$'"),
          isTrue,
        );
        expect(
          migration3Sql.contains('where phone_e164 = v_clean_phone and id != new.id;'),
          isTrue,
        );
      });

      test('Preserves existing user profile columns on phone update', () {
        // In UPDATE branch, only phone_e164 and updated_at are modified
        expect(
          migration3Sql.contains('update public.profiles\n        set phone_e164 = v_clean_phone,'),
          isTrue,
        );
      });
    });

    group('Task D: Direct-Chat Navigation UUID Resolution', () {
      test('ContactsScreen resolves canonical direct chat UUID via RPC before navigating', () {
        final contactsFile = File('lib/features/contacts/presentation/screens/contacts_screen.dart');
        expect(contactsFile.existsSync(), isTrue);
        final content = contactsFile.readAsStringSync();

        expect(content.contains("sb.rpc(\n                        'get_or_create_direct_chat'"), isTrue);
        expect(content.contains("'p_peer_id': p.uid!"), isTrue);
        expect(content.contains("ChatIdService.oneToOne"), isFalse,
            reason: 'Must not use legacy string pair formatting');
      });

      test('openChat validates RFC 4122 UUID and falls back to RPC resolution if non-UUID is supplied', () {
        final chatRouteFile = File('lib/shared/utils/chat_route.dart');
        expect(chatRouteFile.existsSync(), isTrue);
        final content = chatRouteFile.readAsStringSync();

        expect(content.contains('uuidRegex'), isTrue);
        expect(content.contains("'get_or_create_direct_chat'"), isTrue);
        expect(content.contains("'/chats/chat/\$resolvedChatId'"), isTrue);
      });

      test('MessagesRepository exposes getOrCreateDirectChat method', () {
        final messagesRepoFile = File('lib/features/messaging/data/messages_repository.dart');
        expect(messagesRepoFile.existsSync(), isTrue);
        final content = messagesRepoFile.readAsStringSync();

        expect(content.contains('Future<String?> getOrCreateDirectChat(String peerId) async'), isTrue);
        expect(content.contains("'get_or_create_direct_chat'"), isTrue);
      });
    });

    group('Task E: Device Registration Security & Account Switching', () {
      test('OneSignalService routes device persistence through register_device RPC', () {
        final oneSignalFile = File('lib/features/notifications/data/onesignal_service.dart');
        expect(oneSignalFile.existsSync(), isTrue);
        final content = oneSignalFile.readAsStringSync();

        expect(content.contains("await _supabase.rpc(\n        'register_device'"), isTrue);
        expect(content.contains("'p_player_id': cleanPid"), isTrue);
        expect(content.contains("'p_platform': normalized"), isTrue);
        expect(content.contains("from('user_devices').upsert"), isFalse,
            reason: 'Direct upsert on user_devices must be replaced by register_device RPC');
      });

      test('SQL register_device safely reassigns ownership on account switching', () {
        expect(migration3Sql.contains('Account switch detected: Safely reassign token ownership'), isTrue);
        expect(migration3Sql.contains('where player_id = v_clean_player_id\n    returning * into v_device;'), isTrue);
        expect(migration3Sql.contains('set user_id = v_caller_id,'), isTrue);
      });

      test('SQL register_device derives caller strictly from auth.uid() and validates platform', () {
        expect(migration3Sql.contains('v_caller_id uuid := auth.uid();'), isTrue);
        expect(migration3Sql.contains("if v_caller_id is null then\n    raise exception 'Unauthorized: authentication required'"), isTrue);
        expect(migration3Sql.contains("if v_clean_platform not in ('android', 'ios', 'web') then"), isTrue);
        expect(migration3Sql.contains("perform pg_catalog.pg_advisory_xact_lock(v_lock_key);"), isTrue);
      });
    });
  });
}
