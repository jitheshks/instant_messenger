-- ==============================================================================
-- ROLLBACK SCRIPT: 20261104000001_calling_participant_heartbeat_and_liveness.sql
-- Description: Completely restores pre-migration function definitions, drops
--              heartbeat RPC, drops partial indexes, and removes heartbeat columns.
-- Baseline Sources:
--   - initiate_call: 20261102000002_calling_initiate_inline_timeout.sql
--   - accept_call:   20261102000001_calling_schema_and_lifecycle_rpcs.sql:320-419
--   - rejoin_call:   20261102000001_calling_schema_and_lifecycle_rpcs.sql:790-845
--   - process_call_timeouts: 20261102000001_calling_schema_and_lifecycle_rpcs.sql:955-994
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. DROP NEW RPC, FEATURE FLAGS, AND PARTIAL INDEXES
-- ------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.heartbeat_call(uuid);
DROP FUNCTION IF EXISTS public.is_feature_enabled(text);
DROP TABLE IF EXISTS public.app_settings CASCADE;
DROP INDEX IF EXISTS public.idx_call_participants_active_heartbeat;
DROP INDEX IF EXISTS public.idx_calls_ongoing_activity;

-- ------------------------------------------------------------------------------
-- 2. RESTORE EXACT PRE-MIGRATION FUNCTION: initiate_call
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

  SELECT id, status, started_at INTO v_existing_call
  FROM public.calls
  WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
  LIMIT 1
  FOR UPDATE;

  IF v_existing_call.id IS NOT NULL THEN
    IF v_existing_call.status = 'ringing' AND clock_timestamp() >= v_existing_call.started_at + interval '45 seconds' THEN
      UPDATE public.calls
      SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
      WHERE id = v_existing_call.id AND status = 'ringing';

      UPDATE public.call_participants
      SET status = 'missed', updated_at = clock_timestamp()
      WHERE call_id = v_existing_call.id AND status = 'invited';
    ELSE
      RETURN jsonb_build_object(
        'success', false,
        'error', 'call_in_progress',
        'existing_call_id', v_existing_call.id
      );
    END IF;
  END IF;

  v_room_id := gen_random_uuid()::text;

  INSERT INTO public.calls (
    chat_id, caller_id, call_type, is_group, status, room_id, started_at
  ) VALUES (
    p_chat_id, v_caller_id, p_call_type, v_is_group, 'ringing', v_room_id, clock_timestamp()
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

  INSERT INTO public.call_participants (call_id, user_id, status, joined_at)
  VALUES (v_new_call_id, v_caller_id, 'accepted', clock_timestamp());

  INSERT INTO public.call_participants (call_id, user_id, status)
  SELECT v_new_call_id, unnest(p_invitee_ids), 'invited';

  SELECT phone_e164, coalesce(display_name, '') INTO v_caller_phone, v_caller_name
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
    'call_type', p_call_type,
    'is_group', v_is_group,
    'status', 'ringing'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.initiate_call(uuid, text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.initiate_call(uuid, text, uuid[]) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. RESTORE EXACT PRE-MIGRATION FUNCTION: accept_call
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user is not an invited participant of this call' USING errcode = '42501';
  END IF;

  IF v_participant.status = 'accepted' AND v_call.status IN ('ringing', 'ongoing') THEN
    RETURN jsonb_build_object(
      'success', true,
      'call_id', v_call.id,
      'room_id', v_call.room_id,
      'call_type', v_call.call_type,
      'status', v_call.status
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
      'error', 'call_terminated',
      'status', v_call.status
    );
  END IF;

  IF v_call.status = 'ringing' AND clock_timestamp() >= v_call.started_at + interval '45 seconds' THEN
    UPDATE public.calls
    SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
    WHERE id = p_call_id;

    UPDATE public.call_participants
    SET status = 'missed', updated_at = clock_timestamp()
    WHERE call_id = p_call_id AND status = 'invited';

    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_timed_out',
      'status', 'missed'
    );
  END IF;

  UPDATE public.call_participants
  SET status = 'accepted', joined_at = coalesce(joined_at, clock_timestamp()), updated_at = clock_timestamp()
  WHERE id = v_participant.id;

  IF v_call.status = 'ringing' THEN
    UPDATE public.calls
    SET status = 'ongoing', connected_at = coalesce(connected_at, clock_timestamp()), updated_at = clock_timestamp()
    WHERE id = p_call_id;
    v_call.status := 'ongoing';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'call_id', v_call.id,
    'room_id', v_call.room_id,
    'call_type', v_call.call_type,
    'status', v_call.status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_call(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. RESTORE EXACT PRE-MIGRATION FUNCTION: rejoin_call
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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

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

  UPDATE public.call_participants
  SET status = 'accepted', joined_at = clock_timestamp(), left_at = NULL, updated_at = clock_timestamp()
  WHERE id = v_participant.id;

  RETURN jsonb_build_object(
    'success', true,
    'call_id', v_call.id,
    'room_id', v_call.room_id,
    'call_type', v_call.call_type,
    'status', 'ongoing'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rejoin_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rejoin_call(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. RESTORE EXACT PRE-MIGRATION FUNCTION: process_call_timeouts
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
  v_processed_count integer := 0;
BEGIN
  FOR v_call IN
    SELECT id, started_at
    FROM public.calls
    WHERE status = 'ringing'
      AND started_at + interval '45 seconds' <= clock_timestamp()
    ORDER BY started_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    IF clock_timestamp() >= v_call.started_at + interval '45 seconds' THEN
      UPDATE public.calls
      SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
      WHERE id = v_call.id AND status = 'ringing';

      UPDATE public.call_participants
      SET status = 'missed', updated_at = clock_timestamp()
      WHERE call_id = v_call.id AND status = 'invited';

      v_processed_count := v_processed_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'processed_count', v_processed_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_call_timeouts(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_call_timeouts(integer) TO service_role;

-- ------------------------------------------------------------------------------
-- 6. DROP NEW COLUMNS (REVERT SCHEMA EXTENSIONS)
-- ------------------------------------------------------------------------------

ALTER TABLE public.call_participants DROP COLUMN IF EXISTS last_heartbeat_at;
ALTER TABLE public.calls DROP COLUMN IF EXISTS last_activity_at;
ALTER TABLE public.calls DROP COLUMN IF EXISTS migration_grace_until;
