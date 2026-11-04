-- ==============================================================================
-- Migration: 20261102000002_calling_initiate_inline_timeout.sql
-- Description: Adds atomic inline timeout expiry for stale ringing calls and
--              targeted ON CONFLICT handling to initiate_call RPC, preventing
--              uncollected calls from blocking subsequent calls in the same chat.
-- Lock Order:  1. public.chats (FOR UPDATE)
--              2. public.calls (FOR UPDATE)
--              3. public.call_participants (UPDATE / INSERT)
--              4. public.call_outbox (INSERT)
-- ==============================================================================

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

  -- 1. Lock chat row to prevent concurrent call creation race
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

  -- 2. Concurrency check with Atomic Inline Timeout Expiry
  SELECT id, status, started_at INTO v_existing_call
  FROM public.calls
  WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
  LIMIT 1
  FOR UPDATE;

  IF v_existing_call.id IS NOT NULL THEN
    -- If call is ringing and exceeded 45-second timeout window, auto-expire it inline
    IF v_existing_call.status = 'ringing' AND clock_timestamp() >= v_existing_call.started_at + interval '45 seconds' THEN
      UPDATE public.calls
      SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
      WHERE id = v_existing_call.id AND status = 'ringing';

      UPDATE public.call_participants
      SET status = 'missed', updated_at = clock_timestamp()
      WHERE call_id = v_existing_call.id AND status = 'invited';
    ELSE
      -- Call is ongoing or actively ringing within 45s window
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
    chat_id, caller_id, call_type, is_group, status, room_id, started_at
  ) VALUES (
    p_chat_id, v_caller_id, p_call_type, v_is_group, 'ringing', v_room_id, clock_timestamp()
  )
  ON CONFLICT (chat_id) WHERE status IN ('ringing', 'ongoing')
  DO NOTHING
  RETURNING id INTO v_new_call_id;

  IF v_new_call_id IS NULL THEN
    SELECT id, status, started_at INTO v_existing_call
    FROM public.calls
    WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
    LIMIT 1;

    IF v_existing_call.id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'call_in_progress',
        'existing_call_id', v_existing_call.id
      );
    END IF;

    -- Edge case: Conflicting call disappeared/ended concurrently.
    -- Attempt single retry to claim the now-vacant chat slot.
    INSERT INTO public.calls (
      chat_id, caller_id, call_type, is_group, status, room_id, started_at
    ) VALUES (
      p_chat_id, v_caller_id, p_call_type, v_is_group, 'ringing', v_room_id, clock_timestamp()
    )
    ON CONFLICT (chat_id) WHERE status IN ('ringing', 'ongoing')
    DO NOTHING
    RETURNING id INTO v_new_call_id;

    IF v_new_call_id IS NULL THEN
      SELECT id, status, started_at INTO v_existing_call
      FROM public.calls
      WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
      LIMIT 1;

      IF v_existing_call.id IS NOT NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'call_in_progress',
          'existing_call_id', v_existing_call.id
        );
      ELSE
        RETURN jsonb_build_object(
          'success', false,
          'error', 'call_conflict_retry'
        );
      END IF;
    END IF;
  END IF;

  -- 4. Insert participants
  INSERT INTO public.call_participants (call_id, user_id, status, joined_at)
  VALUES (v_new_call_id, v_caller_id, 'accepted', clock_timestamp());

  INSERT INTO public.call_participants (call_id, user_id, status)
  SELECT v_new_call_id, unnest(p_invitee_ids), 'invited';

  SELECT phone_e164, coalesce(display_name, '') INTO v_caller_phone, v_caller_name
  FROM public.profiles
  WHERE id = v_caller_id;

  -- 5. Atomic Transactional Outbox Insert (Dedup Key: call_id || ':initiate')
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

-- Preserve execution grants
REVOKE ALL ON FUNCTION public.initiate_call(uuid, text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.initiate_call(uuid, text, uuid[]) TO authenticated;
