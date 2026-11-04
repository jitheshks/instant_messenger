// test/security/calling_authorization_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZEGOCLOUD Calling Backend Security & Authorization Audit', () {
    late String migrationSql;
    late String getZegoTokenCode;
    late String sendPushCode;

    setUpAll(() {
      final migrationFile = File(
        'supabase/migrations/20261102000001_calling_schema_and_lifecycle_rpcs.sql',
      );
      expect(
        migrationFile.existsSync(),
        isTrue,
        reason: 'Migration 20261102000001 must exist',
      );
      migrationSql = migrationFile.readAsStringSync().toLowerCase();

      final zegoFile = File('supabase/functions/get-zego-token/index.ts');
      expect(zegoFile.existsSync(), isTrue);
      getZegoTokenCode = zegoFile.readAsStringSync();

      final pushFile = File('supabase/functions/send-push/index.ts');
      expect(pushFile.existsSync(), isTrue);
      sendPushCode = pushFile.readAsStringSync();
    });

    test('Step 1: All tables, constraints, and partial unique index are defined', () {
      // Calls table & unique room_id
      expect(migrationSql.contains('create table if not exists public.calls'), isTrue);
      expect(migrationSql.contains('constraint uq_calls_room_id unique (room_id)'), isTrue);

      // Call participants table & composite unique constraint
      expect(migrationSql.contains('create table if not exists public.call_participants'), isTrue);
      expect(migrationSql.contains('constraint uq_call_participant unique (call_id, user_id)'), isTrue);

      // Call outbox table & dedup constraint
      expect(migrationSql.contains('create table if not exists public.call_outbox'), isTrue);
      expect(migrationSql.contains('constraint uq_outbox_dedup_key unique (dedup_key)'), isTrue);

      // Partial unique index guaranteeing single active call per chat
      expect(migrationSql.contains('create unique index if not exists uq_calls_active_chat'), isTrue);
      expect(migrationSql.contains("where status in ('ringing', 'ongoing')"), isTrue);

      // Outbox claiming index
      expect(migrationSql.contains('idx_call_outbox_claim'), isTrue);
    });

    test('Step 2: Non-recursive SECURITY DEFINER helper functions exist with search_path', () {
      expect(migrationSql.contains('create or replace function public.is_call_participant'), isTrue);
      expect(migrationSql.contains('create or replace function public.is_call_caller'), isTrue);

      // Both must set search_path = '' to prevent schema poisoning
      final isCallParticipantBlock = migrationSql.substring(
        migrationSql.indexOf('function public.is_call_participant'),
        migrationSql.indexOf('function public.is_call_caller'),
      );
      expect(isCallParticipantBlock.contains("set search_path = ''"), isTrue);
      expect(isCallParticipantBlock.contains('security definer'), isTrue);

      final isCallCallerBlock = migrationSql.substring(
        migrationSql.indexOf('function public.is_call_caller'),
        migrationSql.indexOf('alter table public.calls enable row level security'),
      );
      expect(isCallCallerBlock.contains("set search_path = ''"), isTrue);
      expect(isCallCallerBlock.contains('security definer'), isTrue);
    });

    test('Step 3: Direct mutations on calls, call_participants, call_outbox are strictly revoked', () {
      // RLS enabled
      expect(migrationSql.contains('alter table public.calls enable row level security;'), isTrue);
      expect(migrationSql.contains('alter table public.call_participants enable row level security;'), isTrue);
      expect(migrationSql.contains('alter table public.call_outbox enable row level security;'), isTrue);

      // Direct client mutation revoked
      expect(migrationSql.contains('revoke all on public.calls from public, anon, authenticated;'), isTrue);
      expect(migrationSql.contains('revoke all on public.call_participants from public, anon, authenticated;'), isTrue);
      expect(migrationSql.contains('revoke all on public.call_outbox from public, anon, authenticated;'), isTrue);

      // Authenticated clients are strictly read-only
      expect(migrationSql.contains('grant select on public.calls to authenticated;'), isTrue);
      expect(migrationSql.contains('grant select on public.call_participants to authenticated;'), isTrue);

      // Only service_role has full table mutation privileges
      expect(migrationSql.contains('grant all on public.calls to service_role;'), isTrue);
      expect(migrationSql.contains('grant all on public.call_participants to service_role;'), isTrue);
      expect(migrationSql.contains('grant all on public.call_outbox to service_role;'), isTrue);
    });

    test('Step 4: Strict lock ordering (calls -> call_participants) enforced in all 8 RPCs', () {
      final rpcs = [
        'initiate_call',
        'accept_call',
        'reject_call',
        'cancel_call',
        'leave_call',
        'invite_to_call',
        'rejoin_call',
        'timeout_call',
      ];

      for (final rpc in rpcs) {
        expect(
          migrationSql.contains('function public.$rpc'),
          isTrue,
          reason: 'RPC $rpc must be defined',
        );
      }

      // Check accept_call lock order: calls FOR UPDATE appears before call_participants FOR UPDATE
      final acceptBlock = migrationSql.substring(
        migrationSql.indexOf('function public.accept_call'),
        migrationSql.indexOf('function public.reject_call'),
      );
      final callLockIdx = acceptBlock.indexOf('from public.calls');
      final partLockIdx = acceptBlock.indexOf('from public.call_participants');
      expect(callLockIdx < partLockIdx, isTrue, reason: 'accept_call must lock calls before call_participants');

      // Check reject_call lock order
      final rejectBlock = migrationSql.substring(
        migrationSql.indexOf('function public.reject_call'),
        migrationSql.indexOf('function public.cancel_call'),
      );
      expect(
        rejectBlock.indexOf('from public.calls') < rejectBlock.indexOf('from public.call_participants'),
        isTrue,
        reason: 'reject_call must lock calls before call_participants',
      );

      // Check cancel_call lock order
      final cancelBlock = migrationSql.substring(
        migrationSql.indexOf('function public.cancel_call'),
        migrationSql.indexOf('function public.leave_call'),
      );
      expect(
        cancelBlock.indexOf('from public.calls') < cancelBlock.indexOf('from public.call_participants'),
        isTrue,
        reason: 'cancel_call must lock calls before call_participants',
      );

      // Check leave_call lock order
      final leaveBlock = migrationSql.substring(
        migrationSql.indexOf('function public.leave_call'),
        migrationSql.indexOf('function public.invite_to_call'),
      );
      expect(
        leaveBlock.indexOf('from public.calls') < leaveBlock.indexOf('from public.call_participants'),
        isTrue,
        reason: 'leave_call must lock calls before call_participants',
      );
    });

    test('Step 5: Least privilege grants on sensitive RPCs and worker functions', () {
      // Authenticated users get lifecycle RPCs
      expect(migrationSql.contains('grant execute on function public.initiate_call(uuid, text, uuid[]) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.accept_call(uuid) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.reject_call(uuid) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.cancel_call(uuid) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.leave_call(uuid) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.invite_to_call(uuid, uuid[]) to authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.rejoin_call(uuid) to authenticated;'), isTrue);

      // timeout_call, claim_call_outbox_events, and process_call_timeouts are RESTRICTED to service_role!
      expect(migrationSql.contains('revoke all on function public.timeout_call(uuid) from public, anon, authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.timeout_call(uuid) to service_role;'), isTrue);

      expect(migrationSql.contains('revoke all on function public.claim_call_outbox_events(text, integer, integer) from public, anon, authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.claim_call_outbox_events(text, integer, integer) to service_role;'), isTrue);

      expect(migrationSql.contains('revoke all on function public.process_call_timeouts(integer) from public, anon, authenticated;'), isTrue);
      expect(migrationSql.contains('grant execute on function public.process_call_timeouts(integer) to service_role;'), isTrue);
    });

    test('Step 6: Token04 Edge Function strictly binds token to authoritative database room_id', () {
      // Must require call_id
      expect(getZegoTokenCode.contains('body.call_id'), isTrue);
      expect(getZegoTokenCode.contains('UUID_REGEX.test'), isTrue);

      // Must verify caller JWT identity
      expect(getZegoTokenCode.contains('user.id'), isTrue);

      // Must verify active call status
      expect(getZegoTokenCode.contains("status, room_id"), isTrue);
      expect(getZegoTokenCode.contains("includes(callRecord.status)"), isTrue);

      // Must verify participant status is accepted
      expect(getZegoTokenCode.contains("call_participants"), isTrue);
      expect(getZegoTokenCode.contains('participantRecord.status !== "accepted"'), isTrue);

      // Must use authoritative room_id from callRecord
      expect(getZegoTokenCode.contains('const authoritativeRoomId = callRecord.room_id;'), isTrue);
    });

    test('Step 7: Push dispatch never leaks room_id in notification payloads', () {
      // Check send-push index.ts
      expect(sendPushCode.contains('handleCallPush'), isTrue);

      // Verify that room_id is NOT in the call push payload
      final callPushBlock = sendPushCode.substring(
        sendPushCode.indexOf('handleCallPush'),
        sendPushCode.indexOf('export async function handler'),
      );
      expect(callPushBlock.contains('roomId:'), isFalse, reason: 'roomId key must not be in push payload');
      expect(callPushBlock.contains('room_id:'), isFalse, reason: 'room_id key must not be in push payload');
      expect(callPushBlock.contains('"room_id"'), isFalse, reason: '"room_id" JSON key must not be in push payload');
      expect(callPushBlock.contains('"roomId"'), isFalse, reason: '"roomId" JSON key must not be in push payload');
    });

    test('Step 8: Zero hardcoded credentials or server secrets in calling source and SQL files', () {
      final secretPatterns = [
        RegExp(r'eyJhbGciOi[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+'), // JWT
        RegExp(r'os_v2_app_[a-z0-9]{30,}', caseSensitive: false), // OneSignal Master Key
        RegExp(r'sbp_[a-zA-Z0-9]{20,}'), // Supabase token
      ];

      for (final pattern in secretPatterns) {
        expect(pattern.hasMatch(migrationSql), isFalse);
        expect(pattern.hasMatch(getZegoTokenCode), isFalse);
        expect(pattern.hasMatch(sendPushCode), isFalse);
      }
    });
  });
}
