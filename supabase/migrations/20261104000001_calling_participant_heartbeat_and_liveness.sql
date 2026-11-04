-- ==============================================================================
-- Migration: 20261104000001_calling_participant_heartbeat_and_liveness.sql
-- Description: Adds server-authoritative participant heartbeat tracking,
--              deadlock-safe heartbeat RPC, idempotent accept heartbeat refresh,
--              and race-safe ongoing call recovery with dedicated migration grace.
-- Lock Hierarchy: 1. public.chats (FOR UPDATE)
--                 2. public.calls (FOR UPDATE)
--                 3. public.call_participants (FOR UPDATE)
--                 4. public.call_outbox (INSERT)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SCHEMA ADDITIONS & DETERMINISTIC HISTORICAL BACKFILL
-- ------------------------------------------------------------------------------

-- Step A: Add nullable columns without immediate defaults
ALTER TABLE public.call_participants 
ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz;

ALTER TABLE public.calls 
ADD COLUMN IF NOT EXISTS last_activity_at timestamptz,
ADD COLUMN IF NOT EXISTS migration_grace_until timestamptz;

-- Step B1: Deterministic backfill for TERMINAL calls and departures (Preserves historical record)
UPDATE public.calls 
SET last_activity_at = COALESCE(ended_at, connected_at, started_at)
WHERE last_activity_at IS NULL
  AND status NOT IN ('ringing', 'ongoing');

UPDATE public.call_participants 
SET last_heartbeat_at = COALESCE(left_at, joined_at, created_at)
WHERE last_heartbeat_at IS NULL
  AND status NOT IN ('accepted');

-- Step B2: Migration-time grace period for ACTIVE ongoing calls
-- Active ongoing calls receive their genuine connected_at / started_at as last_activity_at.
-- Accepted participants receive their genuine joined_at / created_at as last_heartbeat_at.
-- Grace is recorded EXCLUSIVELY in the dedicated column migration_grace_until to prevent
-- contaminating real telemetry or duration calculations with synthetic future dates.
UPDATE public.calls 
SET last_activity_at = COALESCE(connected_at, started_at),
    migration_grace_until = clock_timestamp() + interval '15 minutes'
WHERE last_activity_at IS NULL
  AND status = 'ongoing';

UPDATE public.call_participants cp
SET last_heartbeat_at = COALESCE(cp.joined_at, cp.created_at)
FROM public.calls c
WHERE cp.call_id = c.id
  AND cp.last_heartbeat_at IS NULL
  AND cp.status = 'accepted'
  AND c.status = 'ongoing';

-- Step B3: Ringing calls backfill
UPDATE public.calls 
SET last_activity_at = started_at
WHERE last_activity_at IS NULL
  AND status = 'ringing';

UPDATE public.call_participants cp
SET last_heartbeat_at = c.started_at
FROM public.calls c
WHERE cp.call_id = c.id
  AND cp.last_heartbeat_at IS NULL
  AND cp.status = 'accepted'
  AND c.status = 'ringing';

-- Step C: Assign defaults for all FUTURE inserts
ALTER TABLE public.call_participants 
ALTER COLUMN last_heartbeat_at SET DEFAULT clock_timestamp();

ALTER TABLE public.calls 
ALTER COLUMN last_activity_at SET DEFAULT clock_timestamp();

-- Step D: Partial indexes for performance
CREATE INDEX IF NOT EXISTS idx_call_participants_active_heartbeat 
ON public.call_participants (call_id, last_heartbeat_at) 
WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_calls_ongoing_activity 
ON public.calls (chat_id, last_activity_at) 
WHERE status = 'ongoing';

-- Step E: Safe Rollout Gating (Feature Flags / System Settings)
-- Default state immediately after migration is DISABLED ('false') to protect legacy
-- clients that do not yet emit heartbeats from being prematurely terminated.
CREATE TABLE IF NOT EXISTS public.app_settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  description text,
  updated_at timestamptz DEFAULT clock_timestamp()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.app_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.app_settings TO authenticated, anon;
GRANT ALL ON public.app_settings TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'app_settings' AND policyname = 'app_settings_read'
  ) THEN
    CREATE POLICY "app_settings_read"
      ON public.app_settings
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;

INSERT INTO public.app_settings (key, value, description)
VALUES ('calling_heartbeat_recovery_enabled', 'false', 'Enables ongoing abandoned call recovery via heartbeats')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_feature_enabled(p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT value = 'true' FROM public.app_settings WHERE key = p_key),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_feature_enabled(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_feature_enabled(text) TO authenticated, anon, service_role;

-- ------------------------------------------------------------------------------
-- 2. HARDENED CONCURRENCY-SAFE RPC: heartbeat_call
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.heartbeat_call(
  p_call_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call_status text;
  v_participant_status text;
  v_participant_id uuid;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- Step 1: Lock call row FIRST (Enforces Tier 2 Lock Hierarchy)
  SELECT status INTO v_call_status
  FROM public.calls
  WHERE id = p_call_id
  FOR UPDATE;

  IF v_call_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'call_not_found');
  END IF;

  IF v_call_status != 'ongoing' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_not_ongoing',
      'status', v_call_status
    );
  END IF;

  -- Step 2: Lock participant row SECOND (Enforces Tier 3 Lock Hierarchy)
  SELECT id, status INTO v_participant_id, v_participant_status
  FROM public.call_participants
  WHERE call_id = p_call_id AND user_id = v_user_id
  FOR UPDATE;

  IF v_participant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'participant_not_found');
  END IF;

  IF v_participant_status != 'accepted' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'participant_not_active',
      'status', v_participant_status
    );
  END IF;

  -- Step 3: Mutate timestamps atomically
  UPDATE public.call_participants
  SET last_heartbeat_at = v_now,
      updated_at = v_now
  WHERE id = v_participant_id;

  UPDATE public.calls
  SET last_activity_at = v_now,
      updated_at = v_now
  WHERE id = p_call_id;

  RETURN jsonb_build_object(
    'success', true,
    'heartbeat_at', v_now
  );
END;
$$;

REVOKE ALL ON FUNCTION public.heartbeat_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_call(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. UPDATED RPC: initiate_call (Atomic Inline Ongoing Recovery)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.initiate_call(
  p_chat_id uuid,
  p_call_type text,
  p_invitee_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_chat_type text;
  v_new_call_id uuid;
  v_room_id text;
  v_valid_invitee_count int;
  v_unique_count int;
  v_is_group boolean;
  v_existing_call record;
  v_effective_ended_at timestamptz;
  v_duration int := 0;
  v_last_participant_heartbeat timestamptz;
  v_caller_phone text;
  v_caller_name text;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  IF p_call_type NOT IN ('audio', 'video') THEN
    RAISE EXCEPTION 'Invalid call_type: must be audio or video' USING errcode = '22023';
  END IF;

  IF p_invitee_ids IS NULL OR cardinality(p_invitee_ids) = 0 THEN
    RAISE EXCEPTION 'At least one invitee is required' USING errcode = '22023';
  END IF;

  IF NULL = ANY(p_invitee_ids) THEN
    RAISE EXCEPTION 'Invitee list must not contain NULL elements' USING errcode = '22023';
  END IF;

  IF v_caller_id = ANY(p_invitee_ids) THEN
    RAISE EXCEPTION 'Caller cannot invite themselves' USING errcode = '22023';
  END IF;

  SELECT count(DISTINCT x) INTO v_unique_count FROM unnest(p_invitee_ids) AS x;
  IF v_unique_count != cardinality(p_invitee_ids) THEN
    RAISE EXCEPTION 'Duplicate invitees are not allowed' USING errcode = '22023';
  END IF;

  -- 1. Lock chat row (Tier 1)
  SELECT type INTO v_chat_type
  FROM public.chats
  WHERE id = p_chat_id
  FOR UPDATE;

  IF v_chat_type IS NULL THEN
    RAISE EXCEPTION 'Chat not found' USING errcode = 'P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'Forbidden: caller is not an active member of this chat' USING errcode = '42501';
  END IF;

  SELECT count(DISTINCT user_id) INTO v_valid_invitee_count
  FROM public.chat_members
  WHERE chat_id = p_chat_id AND user_id = ANY(p_invitee_ids);

  IF v_valid_invitee_count != cardinality(p_invitee_ids) THEN
    RAISE EXCEPTION 'All invitees must be active members of the specified chat' USING errcode = '42501';
  END IF;

  IF v_chat_type = 'direct' THEN
    IF cardinality(p_invitee_ids) != 1 THEN
      RAISE EXCEPTION 'Direct chat calls must have exactly one invitee' USING errcode = '22023';
    END IF;
    v_is_group := false;
  ELSE
    v_is_group := true;
  END IF;

  -- 2. Concurrency check with Atomic Inline Timeout Expiry (Tier 2)
  SELECT id, status, started_at, connected_at, last_activity_at, migration_grace_until INTO v_existing_call
  FROM public.calls
  WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
  LIMIT 1
  FOR UPDATE;

  IF v_existing_call.id IS NOT NULL THEN
    -- Check A: Stale ringing call (> 45s window elapsed)
    IF v_existing_call.status = 'ringing' AND clock_timestamp() >= v_existing_call.started_at + interval '45 seconds' THEN
      UPDATE public.calls
      SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
      WHERE id = v_existing_call.id AND status = 'ringing';

      UPDATE public.call_participants
      SET status = 'missed', updated_at = clock_timestamp()
      WHERE call_id = v_existing_call.id AND status = 'invited';

    -- Check B: Abandoned ongoing call (All participants silent for > 90 seconds AND grace period expired)
    -- GATED: Only runs if calling_heartbeat_recovery_enabled feature flag is true!
    ELSIF v_existing_call.status = 'ongoing' AND 
          public.is_feature_enabled('calling_heartbeat_recovery_enabled') AND
          (v_existing_call.migration_grace_until IS NULL OR clock_timestamp() >= v_existing_call.migration_grace_until) AND
          clock_timestamp() >= v_existing_call.last_activity_at + interval '90 seconds' AND 
          NOT EXISTS (
            SELECT 1 FROM public.call_participants
            WHERE call_id = v_existing_call.id 
              AND status = 'accepted' 
              AND last_heartbeat_at >= clock_timestamp() - interval '90 seconds'
          ) THEN
      SELECT MAX(last_heartbeat_at) INTO v_last_participant_heartbeat
      FROM public.call_participants
      WHERE call_id = v_existing_call.id AND status = 'accepted';

      v_effective_ended_at := COALESCE(v_last_participant_heartbeat, v_existing_call.last_activity_at, v_existing_call.connected_at, v_existing_call.started_at);
      v_duration := GREATEST(0, EXTRACT(epoch FROM (v_effective_ended_at - COALESCE(v_existing_call.connected_at, v_existing_call.started_at)))::int);

      UPDATE public.calls
      SET status = 'ended',
          ended_at = v_effective_ended_at,
          duration_seconds = v_duration,
          updated_at = clock_timestamp()
      WHERE id = v_existing_call.id AND status = 'ongoing';

      UPDATE public.call_participants
      SET status = 'left',
          left_at = COALESCE(left_at, last_heartbeat_at, v_effective_ended_at),
          updated_at = clock_timestamp()
      WHERE call_id = v_existing_call.id AND status = 'accepted';

    ELSE
      RETURN jsonb_build_object(
        'success', false,
        'error', 'call_in_progress',
        'existing_call_id', v_existing_call.id
      );
    END IF;
  END IF;

  v_room_id := gen_random_uuid()::text;

  -- 3. Insert call record with native partial-index conflict target
  INSERT INTO public.calls (
    chat_id, caller_id, call_type, is_group, status, room_id, started_at, last_activity_at
  ) VALUES (
    p_chat_id, v_caller_id, p_call_type, v_is_group, 'ringing', v_room_id, clock_timestamp(), clock_timestamp()
  )
  ON CONFLICT (chat_id) WHERE status IN ('ringing', 'ongoing')
  DO NOTHING
  RETURNING id INTO v_new_call_id;

  IF v_new_call_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_in_progress'
    );
  END IF;

  -- 4. Insert caller as accepted participant (Tier 3)
  INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at)
  VALUES (v_new_call_id, v_caller_id, 'accepted', clock_timestamp(), clock_timestamp());

  -- 5. Insert invitees
  INSERT INTO public.call_participants (call_id, user_id, status)
  SELECT v_new_call_id, unnest(p_invitee_ids), 'invited';

  -- 6. Atomic Outbox Insert for push notifications (Tier 4)
  SELECT phone_e164, display_name INTO v_caller_phone, v_caller_name
  FROM public.profiles
  WHERE id = v_caller_id;

  INSERT INTO public.call_outbox (
    call_id, event_type, dedup_key, payload, status
  ) VALUES (
    v_new_call_id,
    'call_invitation',
    v_new_call_id || ':initiate',
    jsonb_build_object(
      'callId', v_new_call_id,
      'chatId', p_chat_id,
      'callerId', v_caller_id,
      'callerName', coalesce(nullif(v_caller_name, ''), v_caller_phone, 'Caller'),
      'callType', p_call_type,
      'inviteeIds', p_invitee_ids,
      'isMidCall', false
    ),
    'pending'
  );

  RETURN jsonb_build_object(
    'success', true,
    'call_id', v_new_call_id,
    'room_id', v_room_id,
    'status', 'ringing',
    'call_type', p_call_type,
    'is_group', v_is_group
  );
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. UPDATED RPC: accept_call (Idempotent Timestamp Refresh)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call record;
  v_participant record;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- 1. Lock call row FIRST (Tier 2)
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  -- 2. Lock participant row SECOND (Tier 3)
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user is not an invited participant of this call' USING errcode = '42501';
  END IF;

  -- 3. Idempotency Check with Timestamp Refresh for Legitimate Re-entry
  IF v_participant.status = 'accepted' AND v_call.status IN ('ringing', 'ongoing') THEN
    UPDATE public.call_participants
    SET last_heartbeat_at = v_now,
        updated_at = v_now
    WHERE id = v_participant.id;

    UPDATE public.calls
    SET last_activity_at = v_now,
        updated_at = v_now
    WHERE id = p_call_id;

    RETURN jsonb_build_object(
      'success', true,
      'call_id', v_call.id,
      'room_id', v_call.room_id,
      'call_type', v_call.call_type,
      'status', v_call.status,
      'idempotent', true,
      'heartbeat_at', v_now
    );
  END IF;

  IF v_participant.status IN ('rejected', 'cancelled', 'left', 'missed') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invitation_' || v_participant.status,
      'status', v_call.status
    );
  END IF;

  IF v_call.status IN ('ended', 'cancelled', 'rejected', 'missed') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_already_' || v_call.status,
      'status', v_call.status
    );
  END IF;

  -- Wall-clock timeout check (45s window)
  IF v_call.status = 'ringing' AND v_now >= v_call.started_at + interval '45 seconds' THEN
    UPDATE public.calls
    SET status = 'missed', ended_at = v_now, updated_at = v_now
    WHERE id = p_call_id;

    UPDATE public.call_participants
    SET status = 'missed', updated_at = v_now
    WHERE call_id = p_call_id AND status = 'invited';

    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_timed_out',
      'status', 'missed'
    );
  END IF;

  -- 4. Transition participant to accepted with fresh heartbeat
  UPDATE public.call_participants
  SET status = 'accepted',
      joined_at = coalesce(joined_at, v_now),
      last_heartbeat_at = v_now,
      updated_at = v_now
  WHERE id = v_participant.id;

  -- 5. Transition call to ongoing with fresh activity timestamp
  IF v_call.status = 'ringing' THEN
    UPDATE public.calls
    SET status = 'ongoing',
        connected_at = coalesce(connected_at, v_now),
        last_activity_at = v_now,
        updated_at = v_now
    WHERE id = p_call_id;
  ELSE
    UPDATE public.calls
    SET last_activity_at = v_now,
        updated_at = v_now
    WHERE id = p_call_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'call_id', v_call.id,
    'room_id', v_call.room_id,
    'call_type', v_call.call_type,
    'status', 'ongoing'
  );
END;
$$;

-- ------------------------------------------------------------------------------
-- 5. UPDATED RPC: rejoin_call (Heartbeat Refresh on Rejoin)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rejoin_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call record;
  v_participant record;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- 1. Lock call row FIRST (Tier 2)
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  IF v_call.status != 'ongoing' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'cannot_rejoin_call_status_' || v_call.status,
      'status', v_call.status
    );
  END IF;

  -- 2. Lock participant row SECOND (Tier 3)
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user was never an authorized participant of this call' USING errcode = '42501';
  END IF;

  IF v_participant.status != 'left' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_status_for_rejoin',
      'current_status', v_participant.status
    );
  END IF;

  -- 3. Transition participant to accepted with fresh heartbeat
  UPDATE public.call_participants
  SET status = 'accepted',
      joined_at = v_now,
      left_at = NULL,
      last_heartbeat_at = v_now,
      updated_at = v_now
  WHERE id = v_participant.id;

  -- 4. Refresh call activity
  UPDATE public.calls
  SET last_activity_at = v_now,
      updated_at = v_now
  WHERE id = p_call_id;

  RETURN jsonb_build_object(
    'success', true,
    'call_id', v_call.id,
    'room_id', v_call.room_id,
    'call_type', v_call.call_type,
    'status', 'ongoing'
  );
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. UPDATED WORKER FUNCTION: process_call_timeouts
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.process_call_timeouts(
  p_batch_size integer DEFAULT 25
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_call record;
  v_ringing_count integer := 0;
  v_ongoing_count integer := 0;
  v_effective_ended_at timestamptz;
  v_duration int := 0;
  v_last_participant_heartbeat timestamptz;
  v_now timestamptz := clock_timestamp();
  v_rows_affected integer := 0;
BEGIN
  -- 1. Expire stale ringing calls (> 45s)
  FOR v_call IN
    SELECT id, started_at
    FROM public.calls
    WHERE status = 'ringing'
      AND started_at + interval '45 seconds' <= v_now
    ORDER BY started_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.calls
    SET status = 'missed', ended_at = v_now, updated_at = v_now
    WHERE id = v_call.id AND status = 'ringing';

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected > 0 THEN
      UPDATE public.call_participants
      SET status = 'missed', updated_at = v_now
      WHERE call_id = v_call.id AND status = 'invited';

      v_ringing_count := v_ringing_count + 1;
    END IF;
  END LOOP;

  -- 2. Expire abandoned ongoing calls (All participants silent for > 90 seconds AND grace period elapsed)
  -- GATED: Only runs if calling_heartbeat_recovery_enabled feature flag is true!
  IF public.is_feature_enabled('calling_heartbeat_recovery_enabled') THEN
    FOR v_call IN
      SELECT c.id, c.started_at, c.connected_at, c.last_activity_at
      FROM public.calls c
      WHERE c.status = 'ongoing'
        AND (c.migration_grace_until IS NULL OR v_now >= c.migration_grace_until)
        AND c.last_activity_at + interval '90 seconds' <= v_now
        AND NOT EXISTS (
          SELECT 1 FROM public.call_participants p
          WHERE p.call_id = c.id 
            AND p.status = 'accepted' 
            AND p.last_heartbeat_at >= v_now - interval '90 seconds'
        )
      ORDER BY c.last_activity_at ASC
      LIMIT p_batch_size
      FOR UPDATE SKIP LOCKED
    LOOP
      SELECT MAX(last_heartbeat_at) INTO v_last_participant_heartbeat
      FROM public.call_participants
      WHERE call_id = v_call.id AND status = 'accepted';

      v_effective_ended_at := COALESCE(v_last_participant_heartbeat, v_call.last_activity_at, v_call.connected_at, v_call.started_at);
      v_duration := GREATEST(0, EXTRACT(epoch FROM (v_effective_ended_at - COALESCE(v_call.connected_at, v_call.started_at)))::int);

      UPDATE public.calls
      SET status = 'ended',
          ended_at = v_effective_ended_at,
          duration_seconds = v_duration,
          updated_at = v_now
      WHERE id = v_call.id AND status = 'ongoing';

      GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
      IF v_rows_affected > 0 THEN
        UPDATE public.call_participants
        SET status = 'left',
            left_at = COALESCE(left_at, last_heartbeat_at, v_effective_ended_at),
            updated_at = v_now
        WHERE call_id = v_call.id AND status = 'accepted';

        v_ongoing_count := v_ongoing_count + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'expired_ringing_count', v_ringing_count,
    'expired_ongoing_count', v_ongoing_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_call_timeouts(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_call_timeouts(integer) TO service_role;
