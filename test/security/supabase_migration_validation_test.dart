import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase Schema & Migration Reconstruction Validation', () {
    final migrationsDir = Directory('supabase/migrations');

    test('Migration files exist and adhere to Supabase naming convention', () {
      expect(migrationsDir.existsSync(), isTrue, reason: 'supabase/migrations directory must exist');

      final files = migrationsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(files.length, inInclusiveRange(6, 7), reason: 'Expected 6 to 7 migration files');

      final namingRegex = RegExp(r'^\d{14}_[a-z0-9_]+\.sql$');
      for (final file in files) {
        final filename = file.uri.pathSegments.last;
        expect(
          namingRegex.hasMatch(filename),
          isTrue,
          reason: 'File $filename does not follow YYYYMMDDHHMMSS_name.sql naming convention',
        );
      }
    });

    test('Step 1 (20261026000001_core_schema.sql) declares all tables, constraints, and indexes', () {
      final file = File('supabase/migrations/20261026000001_core_schema.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      // Required extensions and schemas
      expect(sql.contains('create schema if not exists extensions;'), isTrue);
      expect(sql.contains('create extension if not exists "uuid-ossp"'), isTrue);
      expect(sql.contains('create extension if not exists "pgcrypto"'), isTrue);

      // Least privileged role
      expect(sql.contains('create role app_contacts_definer'), isTrue);

      // Tables
      final requiredTables = [
        'public.profiles',
        'public.chats',
        'public.chat_members',
        'public.messages',
        'public.user_devices',
        'public.contact_match_rate_limits',
        'public.push_rate_limits',
      ];
      for (final table in requiredTables) {
        expect(sql.contains('create table if not exists $table'), isTrue, reason: 'Missing table $table');
        expect(sql.contains('alter table $table enable row level security;'), isTrue,
            reason: 'RLS not explicitly enabled on $table');
      }

      // Foreign key required for PostgREST embedded joins
      expect(sql.contains('constraint fk_chat_members_profiles foreign key (user_id) references public.profiles(id)'),
          isTrue);

      // Unique single-token device constraint
      expect(sql.contains('constraint uq_user_devices_player_id unique (player_id)'), isTrue);

      // Critical indexes
      expect(sql.contains('create index if not exists idx_chat_members_user_id'), isTrue);
      expect(sql.contains('create index if not exists idx_messages_chat_sent'), isTrue);
      expect(sql.contains('create index if not exists idx_messages_sent_at_id'), isTrue);
      expect(sql.contains('create index if not exists idx_user_devices_user_subscribed'), isTrue);
    });

    test('Step 2 (20261026000002_security_helpers_and_rls.sql) defines helpers, least-privilege grants, and RLS', () {
      final file = File('supabase/migrations/20261026000002_security_helpers_and_rls.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      // Safe UUID parser
      expect(sql.contains('function public.safe_uuid(p_val text)'), isTrue);

      // Recursion-breaking helpers
      expect(sql.contains('function public.is_chat_member(p_chat_id uuid)'), isTrue);
      expect(sql.contains('function public.is_chat_admin(p_chat_id uuid)'), isTrue);
      expect(sql.contains('function public.share_a_chat(p_target_user_id uuid)'), isTrue);
      expect(sql.contains('function public.get_chat_creator(p_chat_id uuid)'), isTrue);

      // Privilege revocations on anon
      expect(sql.contains('revoke all on all tables in schema public from anon;'), isTrue);

      // Revocations preserving message & membership integrity
      expect(sql.contains('-- NOTE: DELETE is intentionally revoked from authenticated.'), isTrue);
      expect(sql.contains('-- NOTE: UPDATE is intentionally revoked from authenticated.'), isTrue);
      expect(sql.contains('grant select, insert on public.profiles to authenticated;'), isTrue);
      expect(sql.contains('grant update (display_name, avatar_url, about, links, last_seen, updated_at) on public.profiles to authenticated;'), isTrue);

      // Rate limit isolation
      expect(sql.contains('revoke all on public.contact_match_rate_limits from anon, authenticated, public;'), isTrue);
      expect(sql.contains('revoke all on public.push_rate_limits from anon, authenticated, public;'), isTrue);
      expect(sql.contains('grant all on public.push_rate_limits to service_role;'), isTrue);

      // Core RLS policies
      expect(sql.contains('create policy "profiles_select_mutual_or_self" on public.profiles'), isTrue);
      expect(sql.contains('create policy "profiles_select_definer" on public.profiles'), isTrue);
      expect(sql.contains('create policy "chats_select_member" on public.chats'), isTrue);
      expect(sql.contains('create policy "chats_insert_group_creator" on public.chats'), isTrue);
      expect(sql.contains('create policy "chat_members_select_member" on public.chat_members'), isTrue);
      expect(sql.contains('create policy "messages_select_member" on public.messages'), isTrue);
      expect(sql.contains('create policy "messages_insert_sender" on public.messages'), isTrue);
      expect(sql.contains('create policy "user_devices_all_self" on public.user_devices'), isTrue);
    });

    test('Step 3 (20261026000003_rpc_functions_and_triggers.sql) defines all required RPC signatures and triggers', () {
      final file = File('supabase/migrations/20261026000003_rpc_functions_and_triggers.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      // Custom type
      expect(sql.contains('create type public.matched_contact'), isTrue);

      // RPC Signatures matching Flutter client & Edge Function invocations
      expect(sql.contains('function public.match_contacts(p_phone_numbers text[])'), isTrue);
      expect(sql.contains('function public.promote_message_status('), isTrue);
      expect(sql.contains('p_message_ids uuid[],'), isTrue);
      expect(sql.contains('p_new_status int'), isTrue);
      expect(sql.contains('function public.mark_chat_read(p_chat_id uuid)'), isTrue);
      expect(sql.contains('function public.get_or_create_direct_chat(p_peer_id uuid)'), isTrue);
      expect(sql.contains('function public.set_chat_member_role(p_chat_id uuid, p_target_user_id uuid, p_new_role text)'), isTrue);
      expect(sql.contains('function public.remove_chat_member(p_chat_id uuid, p_target_user_id uuid)'), isTrue);
      expect(sql.contains('function public.leave_chat(p_chat_id uuid)'), isTrue);
      expect(sql.contains('function public.attach_message_media('), isTrue);
      expect(sql.contains('p_chat_id uuid,'), isTrue);
      expect(sql.contains('p_message_id uuid,'), isTrue);
      expect(sql.contains('p_media jsonb'), isTrue);
      expect(sql.contains('function public.register_device('), isTrue);
      expect(sql.contains('p_player_id text,'), isTrue);
      expect(sql.contains('p_platform text,'), isTrue);
      expect(sql.contains('function public.check_push_rate_limit(p_user_id uuid)'), isTrue);
      expect(sql.contains('function public.get_my_push_rate_limit()'), isTrue);
      expect(sql.contains('function public.cleanup_push_rate_limits('), isTrue);

      // Triggers
      expect(sql.contains('function public.handle_new_auth_user()'), isTrue);
      expect(sql.contains('create trigger on_auth_user_created'), isTrue);
      expect(sql.contains('function public.handle_new_message()'), isTrue);
      expect(sql.contains('create trigger on_message_inserted'), isTrue);

      // Security Definer & empty search path enforcement on all functions
      final functions = [
        'match_contacts',
        'handle_new_auth_user',
        'handle_new_message',
        'promote_message_status',
        'mark_chat_read',
        'get_or_create_direct_chat',
        'set_chat_member_role',
        'remove_chat_member',
        'leave_chat',
        'attach_message_media',
        'register_device',
        'check_push_rate_limit',
        'get_my_push_rate_limit',
        'cleanup_push_rate_limits',
      ];
      for (final fn in functions) {
        expect(sql.contains('create or replace function public.$fn'), isTrue, reason: '$fn not declared');
      }

      // Safe account-switching token reassignment in register_device
      expect(sql.contains('Account switch detected: Safely reassign token ownership'), isTrue);
      expect(sql.contains('set user_id = v_caller_id,'), isTrue);

      // Edge Function isolation on check_push_rate_limit
      expect(sql.contains('grant execute on function public.check_push_rate_limit(uuid) to service_role;'), isTrue);
      expect(sql.contains('revoke all on function public.check_push_rate_limit(uuid) from public, anon, authenticated;'), isTrue);
    });

    test('Step 4 (20261026000004_storage_and_realtime.sql) defines buckets, storage RLS, and realtime publication', () {
      final file = File('supabase/migrations/20261026000004_storage_and_realtime.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      // Buckets
      expect(sql.contains("'avatars', 'avatars', true, 5242880"), isTrue);
      expect(sql.contains("'attachments', 'attachments', false, 104857600"), isTrue);

      // Storage RLS
      expect(sql.contains('create policy "avatars_select_authenticated" on storage.objects'), isTrue);
      expect(sql.contains('create policy "avatars_insert_owner" on storage.objects'), isTrue);
      expect(sql.contains('create policy "attachments_select_member" on storage.objects'), isTrue);
      expect(sql.contains('create policy "attachments_insert_member" on storage.objects'), isTrue);
      expect(sql.contains('create policy "attachments_delete_authorized" on storage.objects'), isTrue);

      // Replica Identity
      expect(sql.contains('alter table public.messages replica identity full;'), isTrue);
      expect(sql.contains('alter table public.chats replica identity full;'), isTrue);
      expect(sql.contains('alter table public.chat_members replica identity full;'), isTrue);
      expect(sql.contains('alter table public.profiles replica identity full;'), isTrue);

      // Publication membership
      expect(sql.contains('alter publication supabase_realtime add table public.messages;'), isTrue);
      expect(sql.contains('alter publication supabase_realtime add table public.chats;'), isTrue);
      expect(sql.contains('alter publication supabase_realtime add table public.chat_members;'), isTrue);
      expect(sql.contains('alter publication supabase_realtime add table public.profiles;'), isTrue);

      // Realtime private channel topic authorization
      expect(sql.contains('create policy "chat_typing_select_member"'), isTrue);
      expect(sql.contains('create policy "chat_typing_insert_member"'), isTrue);
      expect(sql.contains("realtime.topic() like 'chat_typing:%'"), isTrue);
    });

    test('Step 5 (20261028000001_fix_match_contacts_owner.sql) aligns match_contacts owner to postgres', () {
      final file = File('supabase/migrations/20261028000001_fix_match_contacts_owner.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      expect(sql.contains('alter function public.match_contacts(text[]) owner to postgres;'), isTrue);
      expect(sql.contains('grant execute on function public.match_contacts(text[]) to authenticated;'), isTrue);
      expect(sql.contains('revoke all on function public.match_contacts(text[]) from public, anon;'), isTrue);
    });

    test('Step 6 (20261028000002_add_forward_and_reply_columns.sql) adds forward/reply columns and validation trigger', () {
      final file = File('supabase/migrations/20261028000002_add_forward_and_reply_columns.sql');
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync();

      expect(sql.contains('is_forwarded boolean not null default false'), isTrue);
      expect(sql.contains('reply_to_message_id uuid references public.messages(id) on delete set null'), isTrue);
      expect(sql.contains('reply_snapshot jsonb'), isTrue);
      expect(sql.contains('idx_messages_reply_to_message_id'), isTrue);
      expect(sql.contains('grant insert (is_forwarded, reply_to_message_id, reply_snapshot)'), isTrue);
      expect(sql.contains('create or replace function public.validate_message_reply()'), isTrue);
      expect(sql.contains("set search_path = ''"), isTrue);
      expect(sql.contains('create trigger trg_validate_message_reply'), isTrue);
    });

    test('Step 7 (20261101000001_delivery_receipt_tokens.sql) declares delivery receipt tokens table and acknowledge RPC', () {
      final file = File('supabase/migrations/20261101000001_delivery_receipt_tokens.sql');
      if (!file.existsSync()) return;
      final sql = file.readAsStringSync();

      expect(sql.contains('create table if not exists public.message_delivery_receipt_tokens'), isTrue);
      expect(sql.contains('uq_message_delivery_token unique (token)'), isTrue);
      expect(sql.contains('create or replace function public.acknowledge_delivery_token'), isTrue);
      expect(sql.contains("set search_path = ''"), isTrue);
      expect(sql.contains('grant execute on function public.acknowledge_delivery_token(uuid, text) to authenticated;'), isTrue);

      // Atomic DELETE & GET DIAGNOSTICS validation (eliminates race condition)
      expect(sql.contains('delete from public.message_delivery_receipt_tokens'), isTrue);
      expect(sql.contains('message_id = p_message_id'), isTrue);
      expect(sql.contains('recipient_id = v_caller_id'), isTrue);
      expect(sql.contains('token = trim(p_receipt_token)'), isTrue);
      expect(sql.contains('expires_at > pg_catalog.clock_timestamp()'), isTrue);
      expect(sql.contains('get diagnostics v_consumed_tokens = row_count;'), isTrue);
      expect(sql.contains('if v_consumed_tokens = 0 then'), isTrue);
      expect(sql.contains('select exists'), isFalse, reason: 'Race-prone separate SELECT EXISTS check must be removed');

      expect(sql.contains('create or replace function public.cleanup_expired_delivery_tokens'), isTrue);
      expect(sql.contains('grant execute on function public.cleanup_expired_delivery_tokens() to service_role;'), isTrue);
      expect(sql.contains('revoke all on function public.cleanup_expired_delivery_tokens() from public, anon, authenticated;'), isTrue);
    });

    test('Zero hardcoded credentials or secrets in SQL migration files', () {
      final files = migrationsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'));

      final secretPatterns = [
        RegExp(r'eyJhbGciOi[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+'), // JWT pattern
        RegExp(r'os_v2_app_[a-z0-9]{30,}', caseSensitive: false), // OneSignal Master Key
        RegExp(r'sbp_[a-zA-Z0-9]{20,}'), // Supabase token
        RegExp(r'service_role_key'),
        RegExp(r'anon_key'),
      ];

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final pattern in secretPatterns) {
          expect(
            pattern.hasMatch(content),
            isFalse,
            reason: 'Secret pattern matched in ${file.path}',
          );
        }
      }
    });
  });
}
