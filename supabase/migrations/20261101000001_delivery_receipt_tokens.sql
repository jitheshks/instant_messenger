-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Step 5: Short-Lived Message Delivery Receipt Tokens & Atomic Acknowledgment RPC
-- File: supabase/migrations/20261101000001_delivery_receipt_tokens.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. MESSAGE DELIVERY RECEIPT TOKENS TABLE
-- ------------------------------------------------------------------------------
-- Holds short-lived (e.g. 24-hour), recipient-specific, message-specific
-- delivery receipt authorization tokens issued exclusively by the backend
-- during push notification dispatch (send-push Edge Function).
create table if not exists public.message_delivery_receipt_tokens (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint uq_message_delivery_token unique (token)
);

create index if not exists idx_delivery_tokens_lookup
  on public.message_delivery_receipt_tokens (message_id, recipient_id, token);

create index if not exists idx_delivery_tokens_expiry
  on public.message_delivery_receipt_tokens (expires_at);

alter table public.message_delivery_receipt_tokens enable row level security;

-- Client roles (anon/authenticated) have ZERO direct table access.
-- Token insertion is restricted to service_role (Edge Functions).
-- Token validation and consumption occurs exclusively via the SECURITY DEFINER RPC.
revoke all on public.message_delivery_receipt_tokens from public, anon, authenticated;
grant all on public.message_delivery_receipt_tokens to service_role;

-- ------------------------------------------------------------------------------
-- 2. ATOMIC DELIVERY ACKNOWLEDGMENT RPC
-- ------------------------------------------------------------------------------
-- Validates & Consumes:
-- 1. Caller identity: must be authenticated (auth.uid() is not null).
-- 2. Atomic token consumption: deletes token matching message_id, recipient_id,
--    exact token string, and expires_at > clock_timestamp().
-- 3. Row count check: if GET DIAGNOSTICS reports row_count = 0 (token invalid,
--    expired, wrong recipient, or already consumed by a concurrent request),
--    returns false immediately without executing message status update.
-- 4. Conversation integrity: caller must be a member of the direct chat.
-- 5. Authorship boundary: sender cannot acknowledge their own message (m.sender_id != caller).
-- 6. Monotonic progression: only advances messages where status < 2 (delivered).
-- 7. Read protection: NEVER marks messages as read (status 3).
-- 8. Chat-level synchronization: ties last_message_status update strictly to
--    successful message update / authorization and chat membership.
-- 9. Authorization enforcement: if message update affects 0 rows, verifies
--    whether the message is already delivered/read under valid authorization;
--    failed authorization (e.g. removed member) returns false and suppresses chat update.
create or replace function public.acknowledge_delivery_token(
  p_message_id uuid,
  p_receipt_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_consumed_tokens int := 0;
  v_updated_count int := 0;
begin
  -- 1. Authentication check
  if v_caller_id is null then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;

  if p_message_id is null or p_receipt_token is null or length(trim(p_receipt_token)) = 0 then
    return false;
  end if;

  -- 2. Atomically validate and consume token in a single DELETE operation
  -- Matches message_id, recipient_id, exact token string, and expiry.
  -- Guarantees that only the first request among concurrent attempts deletes the token.
  delete from public.message_delivery_receipt_tokens
  where message_id = p_message_id
    and recipient_id = v_caller_id
    and token = trim(p_receipt_token)
    and expires_at > pg_catalog.clock_timestamp();

  get diagnostics v_consumed_tokens = row_count;

  -- 3. If zero rows were deleted (missing, wrong recipient, expired, or already consumed), exit immediately
  if v_consumed_tokens = 0 then
    return false;
  end if;

  -- 4. Advance message status to 2 (delivered) forward-only in direct chats
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

  -- 5. Authorization & idempotency validation if zero rows were updated
  if v_updated_count = 0 then
    -- Verify whether the message is already in delivered (2) or read (3) status
    -- under strictly verified chat membership, direct chat type, and sender authorship.
    select count(*) into v_updated_count
    from public.messages m
    join public.chats c on m.chat_id = c.id
    where m.id = p_message_id
      and c.type = 'direct'
      and m.sender_id != v_caller_id
      and m.status >= 2
      and public.is_chat_member(c.id);

    -- If authorization failed (e.g. recipient removed from chat, caller is sender,
    -- chat not direct, or non-existent message), exit with false and suppress chat update.
    if v_updated_count = 0 then
      return false;
    end if;
  end if;

  -- 6. Synchronize chat-level last_message_status if the message is the latest in chat
  -- Authorized membership is guaranteed (v_updated_count > 0).
  -- Only sets last_message_status = 2 if the message is actually at status 2 (delivered),
  -- preventing chat-level regression when the message has already reached status 3 (read).
  update public.chats c
  set last_message_status = 2,
      updated_at = pg_catalog.clock_timestamp()
  where c.type = 'direct'
    and c.last_sender_id != v_caller_id
    and c.last_message_status < 2
    and public.is_chat_member(c.id)
    and exists (
      select 1 from public.messages m
      where m.chat_id = c.id
        and m.id = p_message_id
        and m.sent_at = c.last_message_time
        and m.status = 2
    );

  return true;
end;
$$;

revoke all on function public.acknowledge_delivery_token(uuid, text) from public, anon;
grant execute on function public.acknowledge_delivery_token(uuid, text) to authenticated;

-- ------------------------------------------------------------------------------
-- 3. EXPIRED DELIVERY RECEIPT TOKENS MAINTENANCE RPC
-- ------------------------------------------------------------------------------
-- Purges expired token records that were never consumed (e.g. offline device
-- exceeded token lifetime, or recipient launched app directly).
--
-- Retention Policy:
-- - Tokens are issued with a 24-hour expiration by the send-push Edge Function.
-- - This maintenance function purges records where expires_at has passed.
-- - Utilizes idx_delivery_tokens_expiry for efficient index scans.
--
-- Security:
-- - Gated EXCLUSIVELY to service_role (e.g. administrative maintenance task).
-- - Revoked from PUBLIC, anon, and authenticated to prevent unauthorized execution.
create or replace function public.cleanup_expired_delivery_tokens()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int := 0;
begin
  delete from public.message_delivery_receipt_tokens
  where expires_at < pg_catalog.clock_timestamp();

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_expired_delivery_tokens() from public, anon, authenticated;
grant execute on function public.cleanup_expired_delivery_tokens() to service_role;

