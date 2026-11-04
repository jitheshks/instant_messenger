-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Step 3: Application Triggers, Workflow RPCs, and Security Definer Functions
-- File: supabase/migrations/20261026000003_rpc_functions_and_triggers.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CONTACT MATCHING TYPES, RPC & LEAST-PRIVILEGE GRANTS
-- ------------------------------------------------------------------------------
do $$
begin
  if not exists (select from pg_type where typname = 'matched_contact') then
    create type public.matched_contact as (
      id uuid,
      phone_e164 text,
      display_name text,
      avatar_url text
    );
  end if;
end
$$;

create or replace function public.match_contacts(p_phone_numbers text[])
returns setof public.matched_contact
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  v_current_count int;
  normalized_numbers text[];
begin
  caller_id := auth.uid();
  if caller_id is null then
    raise exception 'Unauthorized: authentication required' using errcode = '42501';
  end if;

  if p_phone_numbers is null or pg_catalog.array_length(p_phone_numbers, 1) is null then
    return;
  end if;

  if pg_catalog.array_length(p_phone_numbers, 1) > 200 then
    raise exception 'Batch limit exceeded: maximum 200 phone numbers allowed' using errcode = '22023';
  end if;

  -- Atomic Concurrency-Safe Sliding Window Rate Limit (10 per 15 min)
  insert into public.contact_match_rate_limits as r (user_id, request_count, window_start)
  values (caller_id, 1, pg_catalog.clock_timestamp())
  on conflict (user_id) do update
  set request_count = case
        when pg_catalog.clock_timestamp() - r.window_start < interval '15 minutes'
        then r.request_count + 1
        else 1
      end,
      window_start = case
        when pg_catalog.clock_timestamp() - r.window_start < interval '15 minutes'
        then r.window_start
        else pg_catalog.clock_timestamp()
      end
  returning r.request_count into v_current_count;

  if v_current_count > 10 then
    raise exception 'Rate limit exceeded: contact sync is limited to 10 requests per 15 minutes'
      using errcode = 'P0001';
  end if;

  select pg_catalog.array_agg(cleaned) into normalized_numbers from (
    select pg_catalog.regexp_replace(n, '[^0-9+]', '', 'g') as cleaned
    from pg_catalog.unnest(p_phone_numbers) as n
    where pg_catalog.regexp_replace(n, '[^0-9+]', '', 'g') ~ '^\+[1-9]\d{6,14}$'
  ) sub;

  if normalized_numbers is null or pg_catalog.array_length(normalized_numbers, 1) = 0 then
    return;
  end if;

  return query
  select p.id, p.phone_e164, p.display_name, p.avatar_url
  from public.profiles p
  where p.phone_e164 = any(normalized_numbers) and p.id != caller_id;
end;
$$;

-- Idempotent ownership transfer with momentary schema CREATE privilege
-- PostgreSQL 17 requires target owner to hold schema CREATE during ALTER ... OWNER TO.
-- CREATE is immediately revoked so app_contacts_definer retains zero persistent schema DDL rights.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_roles r on p.proowner = r.oid
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'match_contacts'
      and r.rolname != 'app_contacts_definer'
  ) then
    grant create on schema public to app_contacts_definer;
    alter function public.match_contacts(text[]) owner to app_contacts_definer;
    revoke create on schema public from app_contacts_definer;
  end if;
end
$$;

revoke all on function public.match_contacts(text[]) from public, anon;
grant execute on function public.match_contacts(text[]) to authenticated;

grant select (id, phone_e164, display_name, avatar_url) on public.profiles to app_contacts_definer;
grant select, insert, update on public.contact_match_rate_limits to app_contacts_definer;

-- ------------------------------------------------------------------------------
-- 2. APPLICATION SYSTEM TRIGGERS
-- ------------------------------------------------------------------------------

-- Automatic profile bootstrap trigger on auth.users: Non-destructive to existing metadata
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clean_phone text;
  v_display_name text;
begin
  -- Strict E.164 phone normalization: Handles both "+<digits>" and "<digits>" formats from GoTrue
  if new.phone is not null and pg_catalog.btrim(new.phone) ~ '^\+?[1-9]\d{6,14}$' then
    v_clean_phone := '+' || pg_catalog.ltrim(pg_catalog.btrim(new.phone), '+');
  else
    v_clean_phone := null;
  end if;
  v_display_name := coalesce(nullif(pg_catalog.btrim(new.raw_user_meta_data->>'display_name'), ''), '');

  if tg_op = 'INSERT' then
    if v_clean_phone is not null then
      -- Free up any stale profile holding this phone number to avoid unique violation
      update public.profiles
      set phone_e164 = null,
          updated_at = pg_catalog.clock_timestamp()
      where phone_e164 = v_clean_phone and id != new.id;

      insert into public.profiles (id, phone_e164, display_name)
      values (new.id, v_clean_phone, v_display_name)
      on conflict (id) do update
      set phone_e164 = excluded.phone_e164,
          updated_at = pg_catalog.clock_timestamp();
    else
      insert into public.profiles (id, phone_e164, display_name)
      values (new.id, null, v_display_name)
      on conflict (id) do nothing;
    end if;

  elsif tg_op = 'UPDATE' then
    if old.phone is distinct from new.phone then
      if v_clean_phone is not null then
        -- Free up any stale profile holding the new phone
        update public.profiles
        set phone_e164 = null,
            updated_at = pg_catalog.clock_timestamp()
        where phone_e164 = v_clean_phone and id != new.id;

        -- Update existing profile phone without wiping display_name, avatar_url, about, links
        update public.profiles
        set phone_e164 = v_clean_phone,
            updated_at = pg_catalog.clock_timestamp()
        where id = new.id;
      else
        update public.profiles
        set phone_e164 = null,
            updated_at = pg_catalog.clock_timestamp()
        where id = new.id;
      end if;

      if not found then
        insert into public.profiles (id, phone_e164, display_name)
        values (new.id, v_clean_phone, v_display_name)
        on conflict (id) do update
        set phone_e164 = excluded.phone_e164,
            updated_at = pg_catalog.clock_timestamp();
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of phone on auth.users
  for each row execute function public.handle_new_auth_user();

-- Auto-update chat preview & increment recipient unread counts
create or replace function public.handle_new_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.chats
  set last_message = case when new.type = 'text' then new.text else '[' || new.type || ']' end,
      last_message_time = new.sent_at,
      last_sender_id = new.sender_id,
      last_message_status = new.status,
      updated_at = pg_catalog.clock_timestamp()
  where id = new.chat_id;

  update public.chat_members
  set unread_count = unread_count + 1
  where chat_id = new.chat_id and user_id != new.sender_id;

  return new;
end;
$$;

drop trigger if exists on_message_inserted on public.messages;
create trigger on_message_inserted
  after insert on public.messages
  for each row execute function public.handle_new_message();

-- ------------------------------------------------------------------------------
-- 3. FORWARD-ONLY MESSAGE STATUS PROMOTION RPCS
-- ------------------------------------------------------------------------------

-- Atomic Forward-Only Message Receipt Promotion RPC (Direct Chats)
create or replace function public.promote_message_status(
  p_message_ids uuid[],
  p_new_status int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_updated_count int := 0;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_new_status not in (2, 3) then
    raise exception 'Invalid status promotion: target status must be 2 (delivered) or 3 (read)' using errcode = '22023';
  end if;

  if p_message_ids is null or pg_catalog.array_length(p_message_ids, 1) is null then
    return 0;
  end if;

  -- Only messages in direct chats where caller is a member, caller is NOT the sender,
  -- and current status is strictly less than p_new_status (forward-only monotonic progression)
  with updated_rows as (
    update public.messages m
    set status = p_new_status,
        updated_at = pg_catalog.clock_timestamp()
    from public.chats c
    where m.id = any(p_message_ids)
      and m.chat_id = c.id
      and c.type = 'direct'
      and m.sender_id != v_caller_id
      and m.status < p_new_status
      and public.is_chat_member(c.id)
    returning m.id, m.chat_id, m.sent_at
  )
  select count(*) into v_updated_count from updated_rows;

  -- Synchronize chat-level last_message_status if affected messages are latest in direct chat
  update public.chats c
  set last_message_status = p_new_status,
      updated_at = pg_catalog.clock_timestamp()
  where c.type = 'direct'
    and c.last_sender_id != v_caller_id
    and c.last_message_status < p_new_status
    and exists (
      select 1 from public.messages m
      where m.chat_id = c.id
        and m.id = any(p_message_ids)
        and m.sent_at = c.last_message_time
    );

  return v_updated_count;
end;
$$;

revoke all on function public.promote_message_status(uuid[], int) from public, anon;
grant execute on function public.promote_message_status(uuid[], int) to authenticated;

-- Atomic Mark Read RPC: supports both 1-on-1 receipts and group read horizons
create or replace function public.mark_chat_read(p_chat_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_chat_type text;
begin
  if v_caller_id is null or not public.is_chat_member(p_chat_id) then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  -- Reset unread count and advance read cursor for caller across all chat types
  update public.chat_members
  set unread_count = 0,
      last_read_at = pg_catalog.clock_timestamp()
  where chat_id = p_chat_id and user_id = v_caller_id;

  select type into v_chat_type from public.chats where id = p_chat_id;

  -- In 1-on-1 direct chats, also transition incoming messages forward to status = 3 (read)
  if v_chat_type = 'direct' then
    update public.messages
    set status = 3,
        updated_at = pg_catalog.clock_timestamp()
    where chat_id = p_chat_id and sender_id != v_caller_id and status < 3;

    update public.chats
    set last_message_status = 3,
        updated_at = pg_catalog.clock_timestamp()
    where id = p_chat_id and last_sender_id != v_caller_id and last_message_status < 3;
  end if;
end;
$$;

revoke all on function public.mark_chat_read(uuid) from public, anon;
grant execute on function public.mark_chat_read(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 4. CHAT CREATION & MEMBERSHIP RPCS
-- ------------------------------------------------------------------------------

-- Advisory-Locked Deterministic Direct Chat Lookup/Creation RPC
create or replace function public.get_or_create_direct_chat(p_peer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_chat_id uuid;
  v_lock_key bigint;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized: authentication required' using errcode = '42501';
  end if;

  if p_peer_id is null or v_caller_id = p_peer_id then
    raise exception 'Invalid peer: cannot create a direct chat with yourself or null peer' using errcode = '22023';
  end if;

  -- Validate peer exists in profiles table
  if not exists (select 1 from public.profiles where id = p_peer_id) then
    raise exception 'Peer user does not exist' using errcode = 'P0002';
  end if;

  -- Advisory transaction lock serializes concurrent creation between this specific pair
  v_lock_key := ('x' || pg_catalog.substr(pg_catalog.md5(least(v_caller_id::text, p_peer_id::text) || ':' || greatest(v_caller_id::text, p_peer_id::text)), 1, 16))::bit(64)::bigint;
  perform pg_catalog.pg_advisory_xact_lock(v_lock_key);

  -- Fast path: existing direct chat
  select cm1.chat_id into v_chat_id
  from public.chat_members cm1
  join public.chat_members cm2 on cm1.chat_id = cm2.chat_id
  join public.chats c on c.id = cm1.chat_id
  where c.type = 'direct' and cm1.user_id = v_caller_id and cm2.user_id = p_peer_id;

  if v_chat_id is not null then
    return v_chat_id;
  end if;

  -- Deterministic UUIDv5 from sorted participants
  v_chat_id := extensions.uuid_generate_v5(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid,
    least(v_caller_id::text, p_peer_id::text) || ':' || greatest(v_caller_id::text, p_peer_id::text)
  );

  -- Atomically insert chat and both chat_members
  insert into public.chats (id, type, created_by)
  values (v_chat_id, 'direct', v_caller_id)
  on conflict (id) do nothing;

  insert into public.chat_members (chat_id, user_id, role)
  values
    (v_chat_id, v_caller_id, 'member'),
    (v_chat_id, p_peer_id, 'member')
  on conflict (chat_id, user_id) do nothing;

  -- Verification check: guarantee mutual membership before returning
  if not exists (
    select 1 from public.chat_members cm1
    join public.chat_members cm2 on cm1.chat_id = cm2.chat_id
    where cm1.chat_id = v_chat_id and cm1.user_id = v_caller_id and cm2.user_id = p_peer_id
  ) then
    raise exception 'Failed to verify mutual direct chat membership' using errcode = 'P0001';
  end if;

  return v_chat_id;
end;
$$;

revoke all on function public.get_or_create_direct_chat(uuid) from public, anon;
grant execute on function public.get_or_create_direct_chat(uuid) to authenticated;

-- Transaction-Safe Admin Role Management (Prevents Last Admin Demotion)
create or replace function public.set_chat_member_role(p_chat_id uuid, p_target_user_id uuid, p_new_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_admin_count int;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_new_role not in ('admin', 'member') then
    raise exception 'Invalid role: must be admin or member' using errcode = '22023';
  end if;

  -- Serialize all role modifications and member changes for this chat
  perform 1 from public.chats where id = p_chat_id for update;
  if not found then
    raise exception 'Chat not found' using errcode = 'P0002';
  end if;

  -- Check caller privilege under lock
  if not public.is_chat_admin(p_chat_id) then
    raise exception 'Unauthorized: admin privilege required' using errcode = '42501';
  end if;

  -- If demoting an existing admin to member, ensure at least one other admin remains
  if p_new_role = 'member' and exists (
    select 1 from public.chat_members
    where chat_id = p_chat_id and user_id = p_target_user_id and role = 'admin'
  ) then
    select count(*) into v_admin_count
    from public.chat_members
    where chat_id = p_chat_id and role = 'admin';

    if v_admin_count <= 1 then
      raise exception 'Operation forbidden: cannot demote the last administrator' using errcode = '22000';
    end if;
  end if;

  update public.chat_members
  set role = p_new_role
  where chat_id = p_chat_id and user_id = p_target_user_id;
end;
$$;

revoke all on function public.set_chat_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.set_chat_member_role(uuid, uuid, text) to authenticated;

-- Transaction-Safe Member Removal & Chat Leaving (Prevents Last Admin Removal)
create or replace function public.remove_chat_member(p_chat_id uuid, p_target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_admin_count int;
  v_target_role text;
  v_other_members_exist boolean;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  -- Serialize all departures/removals on this chat
  perform 1 from public.chats where id = p_chat_id for update;
  if not found then
    return;
  end if;

  -- Caller must either be removing themselves (leaving) OR be a chat admin
  if v_caller_id != p_target_user_id and not public.is_chat_admin(p_chat_id) then
    raise exception 'Unauthorized: cannot remove member without admin privilege' using errcode = '42501';
  end if;

  select role into v_target_role
  from public.chat_members
  where chat_id = p_chat_id and user_id = p_target_user_id;

  if v_target_role is null then
    return; -- Member not found / already removed
  end if;

  -- If target is an admin, check if other members remain and whether this is the last admin
  if v_target_role = 'admin' then
    select count(*) into v_admin_count
    from public.chat_members
    where chat_id = p_chat_id and role = 'admin';

    select exists (
      select 1 from public.chat_members
      where chat_id = p_chat_id and user_id != p_target_user_id
    ) into v_other_members_exist;

    if v_admin_count <= 1 and v_other_members_exist then
      raise exception 'Operation forbidden: cannot leave or remove the last administrator while other members remain' using errcode = '22000';
    end if;
  end if;

  delete from public.chat_members
  where chat_id = p_chat_id and user_id = p_target_user_id;

  -- If chat is now empty, clean up the chat row
  if not exists (select 1 from public.chat_members where chat_id = p_chat_id) then
    delete from public.chats where id = p_chat_id;
  end if;
end;
$$;

create or replace function public.leave_chat(p_chat_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.remove_chat_member(p_chat_id, auth.uid());
end;
$$;

revoke all on function public.remove_chat_member(uuid, uuid) from public, anon;
grant execute on function public.remove_chat_member(uuid, uuid) to authenticated;

revoke all on function public.leave_chat(uuid) from public, anon;
grant execute on function public.leave_chat(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 5. SECURE MEDIA ATTACHMENT RPC
-- ------------------------------------------------------------------------------
-- Secure Media Attachment RPC: narrowly scoped, verifies membership, sender ownership,
-- message/chat consistency, and canonical storage path
create or replace function public.attach_message_media(
  p_chat_id uuid,
  p_message_id uuid,
  p_media jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_sender_id uuid;
  v_msg_type text;
  v_status int;
  v_url text;
  v_sanitized_media jsonb;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized: authentication required' using errcode = '42501';
  end if;

  if not public.is_chat_member(p_chat_id) then
    raise exception 'Forbidden: caller is not a member of this chat' using errcode = '42501';
  end if;

  select sender_id, type, status
  into v_sender_id, v_msg_type, v_status
  from public.messages
  where id = p_message_id and chat_id = p_chat_id;

  if not found then
    raise exception 'Message not found in specified chat' using errcode = 'P0002';
  end if;

  if v_sender_id != v_caller_id then
    raise exception 'Forbidden: only the message sender can attach media' using errcode = '42501';
  end if;

  if v_msg_type != 'media' then
    raise exception 'Invalid message type: media cannot be attached to non-media messages' using errcode = '22023';
  end if;

  if v_status > 2 then
    raise exception 'Invalid state: cannot attach media to an already read message' using errcode = '22023';
  end if;

  if jsonb_typeof(p_media) != 'object' then
    raise exception 'Invalid media payload: JSON object expected' using errcode = '22023';
  end if;

  v_url := p_media->>'url';
  if v_url is null or pg_catalog.length(pg_catalog.btrim(v_url)) = 0 then
    raise exception 'Invalid media payload: url is required' using errcode = '22023';
  end if;

  -- Validate expected object-path format: must start with "{chat_id}/{message_id}"
  if not (v_url like (p_chat_id::text || '/' || p_message_id::text || '%')) then
    raise exception 'Invalid media path: attachment object path must begin with %/%', p_chat_id, p_message_id
      using errcode = '22023';
  end if;

  -- Build strictly sanitized media metadata object
  v_sanitized_media := jsonb_build_object(
    'url', v_url,
    'mime', coalesce(p_media->>'mime', 'application/octet-stream'),
    'size', coalesce((p_media->>'size')::bigint, 0),
    'kind', coalesce(p_media->>'kind', 'file')
  );

  if p_media ? 'fileName' then
    v_sanitized_media := v_sanitized_media || jsonb_build_object('fileName', p_media->>'fileName');
  end if;

  update public.messages
  set media = v_sanitized_media,
      updated_at = pg_catalog.clock_timestamp()
  where id = p_message_id;

  return v_sanitized_media;
end;
$$;

revoke all on function public.attach_message_media(uuid, uuid, jsonb) from public, anon;
grant execute on function public.attach_message_media(uuid, uuid, jsonb) to authenticated;

-- ------------------------------------------------------------------------------
-- 6. DEVICE REGISTRATION RPC (STRICT OWNERSHIP LOCK)
-- ------------------------------------------------------------------------------
-- Derives identity strictly from auth.uid().
-- Enforces single-device ownership with strict anti-squatting protections:
-- If player_id is registered to another user, raises SQLSTATE P0003 (Ownership Conflict).
-- Reassignment requires prior authenticated sign-out cleanup or verified external attestation.
create or replace function public.register_device(
  p_player_id text,
  p_platform text,
  p_app_version text default null,
  p_subscribed boolean default true
)
returns public.user_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_clean_player_id text;
  v_clean_platform text;
  v_clean_version text;
  v_device public.user_devices;
  v_lock_key bigint;
  v_existing_owner uuid;
begin
  -- 1. Authentication check: caller must be authenticated
  if v_caller_id is null then
    raise exception 'Unauthorized: authentication required' using errcode = '42501';
  end if;

  -- 2. Validate player_id
  v_clean_player_id := pg_catalog.btrim(p_player_id);
  if v_clean_player_id is null or pg_catalog.length(v_clean_player_id) = 0 then
    raise exception 'Invalid player_id: must not be empty' using errcode = '22023';
  end if;
  if pg_catalog.length(v_clean_player_id) > 128 then
    raise exception 'Invalid player_id: maximum 128 characters' using errcode = '22023';
  end if;

  -- 3. Validate platform
  v_clean_platform := pg_catalog.lower(pg_catalog.btrim(p_platform));
  if v_clean_platform not in ('android', 'ios', 'web') then
    raise exception 'Invalid platform: must be android, ios, or web' using errcode = '22023';
  end if;

  -- 4. Validate app_version
  v_clean_version := nullif(pg_catalog.btrim(p_app_version), '');
  if v_clean_version is not null and pg_catalog.length(v_clean_version) > 64 then
    raise exception 'Invalid app_version: maximum 64 characters' using errcode = '22023';
  end if;

  -- 5. Advisory transaction lock serializes concurrent registrations on the same player_id
  v_lock_key := ('x' || pg_catalog.substr(pg_catalog.md5('player_lock:' || v_clean_player_id), 1, 16))::bit(64)::bigint;
  perform pg_catalog.pg_advisory_xact_lock(v_lock_key);

  -- 6. Safe Ownership Handover Guard on Account Switching:
  -- Check if token is already registered to a different user
  select user_id into v_existing_owner
  from public.user_devices
  where player_id = v_clean_player_id;

  if v_existing_owner is not null and v_existing_owner != v_caller_id then
    -- Account switch detected: Safely reassign token ownership to the currently authenticated session user.
    -- This ensures that:
    -- 1. The previous account immediately stops receiving push notifications on this device.
    -- 2. The newly authenticated session user receives push notifications on their active device.
    -- 3. Device tokens remain strictly unique across all users without blocking re-registration.
    update public.user_devices
    set user_id = v_caller_id,
        platform = v_clean_platform,
        app_version = v_clean_version,
        subscribed = coalesce(p_subscribed, true),
        last_seen = pg_catalog.clock_timestamp()
    where player_id = v_clean_player_id
    returning * into v_device;

    return v_device;
  end if;

  -- 7. Upsert device registration for caller (insert brand-new or update same-user heartbeat)
  insert into public.user_devices (
    user_id,
    player_id,
    platform,
    app_version,
    subscribed,
    last_seen,
    created_at
  )
  values (
    v_caller_id,
    v_clean_player_id,
    v_clean_platform,
    v_clean_version,
    coalesce(p_subscribed, true),
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  )
  on conflict (player_id) do update
  set platform = excluded.platform,
      app_version = excluded.app_version,
      subscribed = excluded.subscribed,
      last_seen = pg_catalog.clock_timestamp()
  where public.user_devices.user_id = v_caller_id
  returning * into v_device;

  return v_device;
end;
$$;

revoke all on function public.register_device(text, text, text, boolean) from public, anon;
grant execute on function public.register_device(text, text, text, boolean) to authenticated;

-- ------------------------------------------------------------------------------
-- 7. SERVER-CONTROLLED PUSH RATE LIMITING & MAINTENANCE RPCS
-- ------------------------------------------------------------------------------
-- Gated exclusively to service_role (invoked by send-push Edge Function after validating caller JWT).
-- Request limits (30 req) and window duration (60s) are hardcoded server-controlled constants.
create or replace function public.check_push_rate_limit(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_limit constant int := 30;
  c_window_seconds constant int := 60;
  c_window_interval constant interval := interval '60 seconds';
  v_current_count int;
  v_window_start timestamptz;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_allowed boolean;
  v_reset_seconds int;
begin
  -- 1. Authorization check: must be invoked by service_role or administrative superuser
  if current_user not in ('service_role', 'postgres', 'supabase_admin')
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized: service-role privilege required for rate-limiting RPC'
      using errcode = '42501';
  end if;

  -- 2. Validate target user parameter
  if p_user_id is null then
    raise exception 'Invalid argument: user_id is required' using errcode = '22023';
  end if;

  -- 3. Atomic upsert with tumbling window evaluation
  insert into public.push_rate_limits as r (user_id, request_count, window_start)
  values (p_user_id, 1, v_now)
  on conflict (user_id) do update
  set request_count = case
        when pg_catalog.clock_timestamp() - r.window_start < c_window_interval
        then r.request_count + 1
        else 1
      end,
      window_start = case
        when pg_catalog.clock_timestamp() - r.window_start < c_window_interval
        then r.window_start
        else pg_catalog.clock_timestamp()
      end
  returning r.request_count, r.window_start into v_current_count, v_window_start;

  v_allowed := (v_current_count <= c_limit);
  v_reset_seconds := greatest(0, pg_catalog.ceil(extract(epoch from (v_window_start + c_window_interval - pg_catalog.clock_timestamp())))::int);

  return jsonb_build_object(
    'allowed', v_allowed,
    'current_count', v_current_count,
    'limit', c_limit,
    'reset_seconds', v_reset_seconds,
    'window_seconds', c_window_seconds
  );
end;
$$;

revoke all on function public.check_push_rate_limit(uuid) from public, anon, authenticated;
grant execute on function public.check_push_rate_limit(uuid) to service_role;

-- Read-Only Push Rate Limit Inspection RPC (Client Quota Check)
-- Allows authenticated clients to inspect their current rate-limit consumption without incrementing.
create or replace function public.get_my_push_rate_limit()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  c_limit constant int := 30;
  c_window_seconds constant int := 60;
  c_window_interval constant interval := interval '60 seconds';
  v_current_count int := 0;
  v_window_start timestamptz;
  v_reset_seconds int := 0;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized: authentication required' using errcode = '42501';
  end if;

  select request_count, window_start
  into v_current_count, v_window_start
  from public.push_rate_limits
  where user_id = v_caller_id;

  if v_window_start is not null and pg_catalog.clock_timestamp() - v_window_start < c_window_interval then
    v_reset_seconds := greatest(0, pg_catalog.ceil(extract(epoch from (v_window_start + c_window_interval - pg_catalog.clock_timestamp())))::int);
  else
    v_current_count := 0;
    v_reset_seconds := 0;
  end if;

  return jsonb_build_object(
    'current_count', v_current_count,
    'limit', c_limit,
    'reset_seconds', v_reset_seconds,
    'window_seconds', c_window_seconds
  );
end;
$$;

revoke all on function public.get_my_push_rate_limit() from public, anon;
grant execute on function public.get_my_push_rate_limit() to authenticated;

-- Stale Rate Limit Record Cleanup Utility (Protected Retention Floor)
create or replace function public.cleanup_push_rate_limits(p_older_than interval default interval '7 days')
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  -- 1. Authorization check: service_role or admin
  if current_user not in ('service_role', 'postgres', 'supabase_admin')
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized: service-role privilege required' using errcode = '42501';
  end if;

  -- 2. Floor guard: must retain at least 1 day of records to prevent clearing active windows
  if p_older_than < interval '1 day' then
    raise exception 'Invalid cleanup threshold: retention period must be at least 1 day'
      using errcode = '22023';
  end if;

  delete from public.push_rate_limits
  where window_start < pg_catalog.clock_timestamp() - p_older_than;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_push_rate_limits(interval) from public, anon, authenticated;
grant execute on function public.cleanup_push_rate_limits(interval) to service_role;

-- ------------------------------------------------------------------------------
-- 8. IDEMPOTENT PROFILE BACKFILL FOR PRE-EXISTING AUTH USERS
-- ------------------------------------------------------------------------------
-- Ensures all users existing in auth.users prior to migration execution acquire
-- a profile row, preserving existing profile metadata, avoiding fake phone numbers,
-- and gracefully handling any duplicate phone entries in dirty legacy auth data.
with candidate_users as (
  select
    u.id,
    case
      when nullif(pg_catalog.btrim(u.phone), '') ~ '^\+?[1-9]\d{6,14}$'
      then '+' || pg_catalog.ltrim(pg_catalog.btrim(u.phone), '+')
      else null
    end as clean_phone,
    coalesce(nullif(pg_catalog.btrim(u.raw_user_meta_data->>'display_name'), ''), '') as clean_name,
    coalesce(u.created_at, pg_catalog.clock_timestamp()) as user_created_at,
    row_number() over (
      partition by case
        when nullif(pg_catalog.btrim(u.phone), '') ~ '^\+?[1-9]\d{6,14}$'
        then '+' || pg_catalog.ltrim(pg_catalog.btrim(u.phone), '+')
        else null
      end
      order by u.created_at asc nulls last
    ) as phone_rank
  from auth.users u
  where not exists (select 1 from public.profiles p where p.id = u.id)
)
insert into public.profiles (id, phone_e164, display_name, created_at, updated_at)
select
  c.id,
  case
    when c.clean_phone is not null
         and c.phone_rank = 1
         and not exists (
           select 1 from public.profiles ep
           where ep.phone_e164 = c.clean_phone
         )
    then c.clean_phone
    else null
  end as phone_e164,
  c.clean_name,
  c.user_created_at,
  pg_catalog.clock_timestamp()
from candidate_users c
on conflict (id) do nothing;
