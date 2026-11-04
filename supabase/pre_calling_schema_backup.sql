


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."matched_contact" AS (
	"id" "uuid",
	"phone_e164" "text",
	"display_name" "text",
	"avatar_url" "text"
);


ALTER TYPE "public"."matched_contact" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."acknowledge_delivery_token"("p_message_id" "uuid", "p_receipt_token" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_caller_id uuid := auth.uid();
  v_consumed_tokens int := 0;
  v_updated_count int := 0;
begin
  -- Authentication check
  if v_caller_id is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_message_id is null
     or p_receipt_token is null
     or length(trim(p_receipt_token)) = 0 then
    return false;
  end if;

  -- Atomically validate and consume the receipt token
  delete from public.message_delivery_receipt_tokens
  where message_id = p_message_id
    and recipient_id = v_caller_id
    and token = trim(p_receipt_token)
    and expires_at > pg_catalog.clock_timestamp();

  get diagnostics v_consumed_tokens = row_count;

  if v_consumed_tokens = 0 then
    return false;
  end if;

  -- Advance message status to delivered (2), never regress read status (3)
  with updated_rows as (
    update public.messages m
    set status = 2,
        updated_at = pg_catalog.clock_timestamp()
    from public.chats c
    where m.id = p_message_id
      and m.chat_id = c.id
      and c.type = 'direct'
      and m.sender_id != v_caller_id
      and m.status < 2
      and public.is_chat_member(c.id)
    returning m.id, m.chat_id, m.sent_at
  )
  select count(*) into v_updated_count from updated_rows;

  -- Validate authorization and idempotency if no message was updated
  if v_updated_count = 0 then
    select count(*) into v_updated_count
    from public.messages m
    join public.chats c on m.chat_id = c.id
    where m.id = p_message_id
      and c.type = 'direct'
      and m.sender_id != v_caller_id
      and m.status >= 2
      and public.is_chat_member(c.id);

    if v_updated_count = 0 then
      return false;
    end if;
  end if;

  -- Synchronize chat-level delivery status only for a delivered message
  update public.chats c
  set last_message_status = 2,
      updated_at = pg_catalog.clock_timestamp()
  where c.type = 'direct'
    and c.last_sender_id != v_caller_id
    and c.last_message_status < 2
    and public.is_chat_member(c.id)
    and exists (
      select 1
      from public.messages m
      where m.chat_id = c.id
        and m.id = p_message_id
        and m.sent_at = c.last_message_time
        and m.status = 2
    );

  return true;
end;
$$;


ALTER FUNCTION "public"."acknowledge_delivery_token"("p_message_id" "uuid", "p_receipt_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attach_message_media"("p_chat_id" "uuid", "p_message_id" "uuid", "p_media" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."attach_message_media"("p_chat_id" "uuid", "p_message_id" "uuid", "p_media" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_push_rate_limit"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."check_push_rate_limit"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_expired_delivery_tokens"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_deleted int := 0;
begin
  delete from public.message_delivery_receipt_tokens
  where expires_at < pg_catalog.clock_timestamp();

  get diagnostics v_deleted = row_count;

  return v_deleted;
end;
$$;


ALTER FUNCTION "public"."cleanup_expired_delivery_tokens"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_push_rate_limits"("p_older_than" interval DEFAULT '7 days'::interval) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."cleanup_push_rate_limits"("p_older_than" interval) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_chat_creator"("p_chat_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select created_by from public.chats
  where id = p_chat_id
    and (created_by = auth.uid() or exists (select 1 from public.chat_members where chat_id = p_chat_id and user_id = auth.uid()));
$$;


ALTER FUNCTION "public"."get_chat_creator"("p_chat_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_push_rate_limit"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_my_push_rate_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_direct_chat"("p_peer_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_or_create_direct_chat"("p_peer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."handle_new_message"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_chat_admin"("p_chat_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.chat_members
    where chat_id = p_chat_id and user_id = auth.uid() and role = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_chat_admin"("p_chat_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_chat_member"("p_chat_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.chat_members
    where chat_id = p_chat_id and user_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."is_chat_member"("p_chat_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_chat"("p_chat_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform public.remove_chat_member(p_chat_id, auth.uid());
end;
$$;


ALTER FUNCTION "public"."leave_chat"("p_chat_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_chat_read"("p_chat_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."mark_chat_read"("p_chat_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_contacts"("p_phone_numbers" "text"[]) RETURNS SETOF "public"."matched_contact"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."match_contacts"("p_phone_numbers" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."promote_message_status"("p_message_ids" "uuid"[], "p_new_status" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."promote_message_status"("p_message_ids" "uuid"[], "p_new_status" integer) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."user_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "player_id" "text" NOT NULL,
    "platform" "text" DEFAULT 'android'::"text" NOT NULL,
    "app_version" "text",
    "subscribed" boolean DEFAULT true NOT NULL,
    "last_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_devices_app_version_check" CHECK ((("app_version" IS NULL) OR ("length"("app_version") <= 64))),
    CONSTRAINT "user_devices_platform_check" CHECK (("platform" = ANY (ARRAY['android'::"text", 'ios'::"text", 'web'::"text"]))),
    CONSTRAINT "user_devices_player_id_check" CHECK (("length"(TRIM(BOTH FROM "player_id")) > 0))
);


ALTER TABLE "public"."user_devices" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_device"("p_player_id" "text", "p_platform" "text", "p_app_version" "text" DEFAULT NULL::"text", "p_subscribed" boolean DEFAULT true) RETURNS "public"."user_devices"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."register_device"("p_player_id" "text", "p_platform" "text", "p_app_version" "text", "p_subscribed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_chat_member"("p_chat_id" "uuid", "p_target_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."remove_chat_member"("p_chat_id" "uuid", "p_target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."safe_uuid"("p_val" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" IMMUTABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
begin
  if p_val is not null and p_val ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return p_val::uuid;
  end if;
  return null;
exception
  when others then
    return null;
end;
$_$;


ALTER FUNCTION "public"."safe_uuid"("p_val" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_chat_member_role"("p_chat_id" "uuid", "p_target_user_id" "uuid", "p_new_role" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."set_chat_member_role"("p_chat_id" "uuid", "p_target_user_id" "uuid", "p_new_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."share_a_chat"("p_target_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.chat_members cm1
    join public.chat_members cm2 on cm1.chat_id = cm2.chat_id
    where cm1.user_id = auth.uid() and cm2.user_id = p_target_user_id
  );
$$;


ALTER FUNCTION "public"."share_a_chat"("p_target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_message_reply"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.reply_to_message_id is not null then
    if not exists (
      select 1 from public.messages
      where id = new.reply_to_message_id and chat_id = new.chat_id
    ) then
      raise exception 'reply_to_message_id must belong to the same chat'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."validate_message_reply"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_members" (
    "chat_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "unread_count" integer DEFAULT 0 NOT NULL,
    "muted" boolean DEFAULT false NOT NULL,
    "last_read_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chat_members_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'member'::"text"])))
);

ALTER TABLE ONLY "public"."chat_members" REPLICA IDENTITY FULL;


ALTER TABLE "public"."chat_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "text" DEFAULT 'direct'::"text" NOT NULL,
    "title" "text" DEFAULT ''::"text" NOT NULL,
    "avatar_url" "text",
    "created_by" "uuid",
    "last_message" "text" DEFAULT ''::"text" NOT NULL,
    "last_message_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_sender_id" "uuid",
    "last_message_status" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chats_type_check" CHECK (("type" = ANY (ARRAY['direct'::"text", 'group'::"text"])))
);

ALTER TABLE ONLY "public"."chats" REPLICA IDENTITY FULL;


ALTER TABLE "public"."chats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_match_rate_limits" (
    "user_id" "uuid" NOT NULL,
    "request_count" integer DEFAULT 1 NOT NULL,
    "window_start" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."contact_match_rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."message_delivery_receipt_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid" NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."message_delivery_receipt_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "type" "text" DEFAULT 'text'::"text" NOT NULL,
    "text" "text" DEFAULT ''::"text" NOT NULL,
    "media" "jsonb",
    "status" integer DEFAULT 1 NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_forwarded" boolean DEFAULT false NOT NULL,
    "reply_to_message_id" "uuid",
    "reply_snapshot" "jsonb",
    CONSTRAINT "chk_messages_status" CHECK (("status" = ANY (ARRAY[0, 1, 2, 3]))),
    CONSTRAINT "messages_type_check" CHECK (("type" = ANY (ARRAY['text'::"text", 'media'::"text", 'call'::"text"])))
);

ALTER TABLE ONLY "public"."messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "phone_e164" "text",
    "display_name" "text" DEFAULT ''::"text" NOT NULL,
    "avatar_url" "text",
    "about" "text" DEFAULT 'Hey there! I am using Instant Messenger.'::"text" NOT NULL,
    "links" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "last_seen" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."profiles" REPLICA IDENTITY FULL;


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_rate_limits" (
    "user_id" "uuid" NOT NULL,
    "request_count" integer DEFAULT 1 NOT NULL,
    "window_start" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."push_rate_limits" OWNER TO "postgres";


ALTER TABLE ONLY "public"."chat_members"
    ADD CONSTRAINT "chat_members_pkey" PRIMARY KEY ("chat_id", "user_id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_match_rate_limits"
    ADD CONSTRAINT "contact_match_rate_limits_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."message_delivery_receipt_tokens"
    ADD CONSTRAINT "message_delivery_receipt_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_phone_e164_key" UNIQUE ("phone_e164");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_rate_limits"
    ADD CONSTRAINT "push_rate_limits_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."message_delivery_receipt_tokens"
    ADD CONSTRAINT "uq_message_delivery_token" UNIQUE ("token");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "uq_user_devices_player_id" UNIQUE ("player_id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_chat_members_user_id" ON "public"."chat_members" USING "btree" ("user_id");



CREATE INDEX "idx_chats_updated_at" ON "public"."chats" USING "btree" ("updated_at" DESC);



CREATE INDEX "idx_delivery_tokens_expiry" ON "public"."message_delivery_receipt_tokens" USING "btree" ("expires_at");



CREATE INDEX "idx_delivery_tokens_lookup" ON "public"."message_delivery_receipt_tokens" USING "btree" ("message_id", "recipient_id", "token");



CREATE INDEX "idx_messages_chat_sent" ON "public"."messages" USING "btree" ("chat_id", "sent_at" DESC);



CREATE INDEX "idx_messages_reply_to_message_id" ON "public"."messages" USING "btree" ("reply_to_message_id") WHERE ("reply_to_message_id" IS NOT NULL);



CREATE INDEX "idx_messages_sent_at_id" ON "public"."messages" USING "btree" ("sent_at", "id");



CREATE INDEX "idx_user_devices_user_subscribed" ON "public"."user_devices" USING "btree" ("user_id") WHERE ("subscribed" = true);



CREATE OR REPLACE TRIGGER "on_message_inserted" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_message"();



CREATE OR REPLACE TRIGGER "trg_validate_message_reply" BEFORE INSERT OR UPDATE OF "reply_to_message_id" ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."validate_message_reply"();



ALTER TABLE ONLY "public"."chat_members"
    ADD CONSTRAINT "chat_members_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_members"
    ADD CONSTRAINT "chat_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_last_sender_id_fkey" FOREIGN KEY ("last_sender_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contact_match_rate_limits"
    ADD CONSTRAINT "contact_match_rate_limits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_members"
    ADD CONSTRAINT "fk_chat_members_profiles" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_delivery_receipt_tokens"
    ADD CONSTRAINT "message_delivery_receipt_tokens_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_delivery_receipt_tokens"
    ADD CONSTRAINT "message_delivery_receipt_tokens_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_message_id_fkey" FOREIGN KEY ("reply_to_message_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_rate_limits"
    ADD CONSTRAINT "push_rate_limits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."chat_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_members_insert_authorized" ON "public"."chat_members" FOR INSERT TO "authenticated" WITH CHECK (((("auth"."uid"() = "public"."get_chat_creator"("chat_id")) OR "public"."is_chat_admin"("chat_id")) AND (EXISTS ( SELECT 1
   FROM "public"."chats" "c"
  WHERE (("c"."id" = "chat_members"."chat_id") AND ("c"."type" = 'group'::"text"))))));



CREATE POLICY "chat_members_select_member" ON "public"."chat_members" FOR SELECT TO "authenticated" USING ("public"."is_chat_member"("chat_id"));



CREATE POLICY "chat_members_update_self_preferences" ON "public"."chat_members" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK ((("auth"."uid"() = "user_id") AND ("role" = ANY (ARRAY['admin'::"text", 'member'::"text"]))));



ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chats_insert_group_creator" ON "public"."chats" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "created_by") AND ("type" = 'group'::"text")));



CREATE POLICY "chats_select_member" ON "public"."chats" FOR SELECT TO "authenticated" USING ("public"."is_chat_member"("id"));



CREATE POLICY "chats_update_admin_or_creator" ON "public"."chats" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "created_by") OR "public"."is_chat_admin"("id"))) WITH CHECK ((("auth"."uid"() = "created_by") OR "public"."is_chat_admin"("id")));



ALTER TABLE "public"."contact_match_rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."message_delivery_receipt_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_insert_sender" ON "public"."messages" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "sender_id") AND "public"."is_chat_member"("chat_id") AND ("status" = ANY (ARRAY[0, 1])) AND ("type" = ANY (ARRAY['text'::"text", 'media'::"text", 'call'::"text"]))));



CREATE POLICY "messages_select_member" ON "public"."messages" FOR SELECT TO "authenticated" USING ("public"."is_chat_member"("chat_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_insert_self" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "id") AND (NOT ("phone_e164" IS DISTINCT FROM NULLIF(("auth"."jwt"() ->> 'phone'::"text"), ''::"text")))));



CREATE POLICY "profiles_select_definer" ON "public"."profiles" FOR SELECT TO "app_contacts_definer" USING (true);



CREATE POLICY "profiles_select_mutual_or_self" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "id") OR "public"."share_a_chat"("id")));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



ALTER TABLE "public"."push_rate_limits" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "push_rate_limits_service_all" ON "public"."push_rate_limits" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "rate_limits_definer_all" ON "public"."contact_match_rate_limits" TO "app_contacts_definer" USING (true) WITH CHECK (true);



ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_devices_all_self" ON "public"."user_devices" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_members";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chats";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "app_contacts_definer";






















































































































































REVOKE ALL ON FUNCTION "public"."acknowledge_delivery_token"("p_message_id" "uuid", "p_receipt_token" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."acknowledge_delivery_token"("p_message_id" "uuid", "p_receipt_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."acknowledge_delivery_token"("p_message_id" "uuid", "p_receipt_token" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attach_message_media"("p_chat_id" "uuid", "p_message_id" "uuid", "p_media" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attach_message_media"("p_chat_id" "uuid", "p_message_id" "uuid", "p_media" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."attach_message_media"("p_chat_id" "uuid", "p_message_id" "uuid", "p_media" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_push_rate_limit"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_push_rate_limit"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cleanup_expired_delivery_tokens"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cleanup_expired_delivery_tokens"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cleanup_push_rate_limits"("p_older_than" interval) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cleanup_push_rate_limits"("p_older_than" interval) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_chat_creator"("p_chat_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_chat_creator"("p_chat_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_chat_creator"("p_chat_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_push_rate_limit"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_push_rate_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_push_rate_limit"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_or_create_direct_chat"("p_peer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_or_create_direct_chat"("p_peer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_direct_chat"("p_peer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_message"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_chat_admin"("p_chat_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_chat_admin"("p_chat_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_chat_admin"("p_chat_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_chat_member"("p_chat_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_chat_member"("p_chat_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_chat_member"("p_chat_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."leave_chat"("p_chat_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_chat"("p_chat_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."leave_chat"("p_chat_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_chat_read"("p_chat_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_chat_read"("p_chat_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_chat_read"("p_chat_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."match_contacts"("p_phone_numbers" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."match_contacts"("p_phone_numbers" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_contacts"("p_phone_numbers" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."promote_message_status"("p_message_ids" "uuid"[], "p_new_status" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."promote_message_status"("p_message_ids" "uuid"[], "p_new_status" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."promote_message_status"("p_message_ids" "uuid"[], "p_new_status" integer) TO "service_role";



GRANT ALL ON TABLE "public"."user_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."user_devices" TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_device"("p_player_id" "text", "p_platform" "text", "p_app_version" "text", "p_subscribed" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_device"("p_player_id" "text", "p_platform" "text", "p_app_version" "text", "p_subscribed" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_device"("p_player_id" "text", "p_platform" "text", "p_app_version" "text", "p_subscribed" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_chat_member"("p_chat_id" "uuid", "p_target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_chat_member"("p_chat_id" "uuid", "p_target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_chat_member"("p_chat_id" "uuid", "p_target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."safe_uuid"("p_val" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."safe_uuid"("p_val" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."safe_uuid"("p_val" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_chat_member_role"("p_chat_id" "uuid", "p_target_user_id" "uuid", "p_new_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_chat_member_role"("p_chat_id" "uuid", "p_target_user_id" "uuid", "p_new_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_chat_member_role"("p_chat_id" "uuid", "p_target_user_id" "uuid", "p_new_role" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."share_a_chat"("p_target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."share_a_chat"("p_target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."share_a_chat"("p_target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_message_reply"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_message_reply"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_message_reply"() TO "service_role";


















GRANT ALL ON TABLE "public"."chat_members" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_members" TO "service_role";



GRANT INSERT("chat_id") ON TABLE "public"."chat_members" TO "authenticated";



GRANT INSERT("user_id") ON TABLE "public"."chat_members" TO "authenticated";



GRANT INSERT("role") ON TABLE "public"."chat_members" TO "authenticated";



GRANT UPDATE("unread_count") ON TABLE "public"."chat_members" TO "authenticated";



GRANT UPDATE("muted") ON TABLE "public"."chat_members" TO "authenticated";



GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";



GRANT INSERT("id") ON TABLE "public"."chats" TO "authenticated";



GRANT INSERT("type") ON TABLE "public"."chats" TO "authenticated";



GRANT INSERT("title"),UPDATE("title") ON TABLE "public"."chats" TO "authenticated";



GRANT INSERT("avatar_url"),UPDATE("avatar_url") ON TABLE "public"."chats" TO "authenticated";



GRANT INSERT("created_by") ON TABLE "public"."chats" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."chats" TO "authenticated";



GRANT ALL ON TABLE "public"."contact_match_rate_limits" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."contact_match_rate_limits" TO "app_contacts_definer";



GRANT ALL ON TABLE "public"."message_delivery_receipt_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT INSERT("id") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("chat_id") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("sender_id") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("type") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("text") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("media") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("status") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("sent_at") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("is_forwarded") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("reply_to_message_id") ON TABLE "public"."messages" TO "authenticated";



GRANT INSERT("reply_snapshot") ON TABLE "public"."messages" TO "authenticated";



GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."profiles" TO "app_contacts_definer";



GRANT SELECT("phone_e164") ON TABLE "public"."profiles" TO "app_contacts_definer";



GRANT UPDATE("display_name") ON TABLE "public"."profiles" TO "authenticated";
GRANT SELECT("display_name") ON TABLE "public"."profiles" TO "app_contacts_definer";



GRANT UPDATE("avatar_url") ON TABLE "public"."profiles" TO "authenticated";
GRANT SELECT("avatar_url") ON TABLE "public"."profiles" TO "app_contacts_definer";



GRANT UPDATE("about") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("links") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("last_seen") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."push_rate_limits" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































