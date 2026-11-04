-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Phase 1 Calling: calls, call_participants, call_outbox, non-recursive RLS, RPCs
-- File: supabase/migrations/20261102000001_calling_schema_and_lifecycle_rpcs.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TABLES & CONSTRAINTS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id uuid NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  caller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  call_type text NOT NULL CHECK (call_type IN ('audio', 'video')),
  is_group boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'ringing' 
    CHECK (status IN ('ringing', 'ongoing', 'ended', 'rejected', 'missed', 'cancelled')),
  room_id text NOT NULL DEFAULT gen_random_uuid()::text,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  connected_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT uq_calls_room_id UNIQUE (room_id)
);

CREATE TABLE IF NOT EXISTS public.call_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'invited' 
    CHECK (status IN ('invited', 'accepted', 'rejected', 'left', 'busy', 'cancelled', 'missed')),
  joined_at timestamptz,
  left_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT uq_call_participant UNIQUE (call_id, user_id)
);

-- Transactional Outbox for Server-Side Push Dispatch
CREATE TABLE IF NOT EXISTS public.call_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('call_invitation', 'call_cancelled')),
  dedup_key text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'dispatched', 'failed')),
  retry_count integer NOT NULL DEFAULT 0,
  max_retries integer NOT NULL DEFAULT 3,
  locked_until timestamptz,
  locked_by text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  dispatched_at timestamptz,
  CONSTRAINT uq_outbox_dedup_key UNIQUE (dedup_key)
);

-- Partial Unique Index: Guarantees single active call per chat at the storage engine level
CREATE UNIQUE INDEX IF NOT EXISTS uq_calls_active_chat 
  ON public.calls (chat_id) 
  WHERE status IN ('ringing', 'ongoing');

-- Performance & Foreign Key Indexes
CREATE INDEX IF NOT EXISTS idx_calls_chat_id ON public.calls (chat_id);
CREATE INDEX IF NOT EXISTS idx_calls_caller_id ON public.calls (caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_status ON public.calls (status);
CREATE INDEX IF NOT EXISTS idx_call_participants_call_id ON public.call_participants (call_id);
CREATE INDEX IF NOT EXISTS idx_call_participants_user_id ON public.call_participants (user_id);
CREATE INDEX IF NOT EXISTS idx_call_participants_user_status ON public.call_participants (user_id, status);
CREATE INDEX IF NOT EXISTS idx_call_outbox_claim ON public.call_outbox (status, locked_until, retry_count);

-- ------------------------------------------------------------------------------
-- 2. RECURSION-BREAKING SECURITY DEFINER HELPERS
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_call_participant(p_call_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.call_participants
    WHERE call_id = p_call_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_call_caller(p_call_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.calls
    WHERE id = p_call_id AND caller_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_call_participant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_call_participant(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_call_caller(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_call_caller(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY & LEAST-PRIVILEGE GRANTS
-- ------------------------------------------------------------------------------

ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY "calls_select_authorized" ON public.calls
  FOR SELECT TO authenticated
  USING (
    caller_id = (SELECT auth.uid()) OR
    public.is_call_participant(id) OR
    public.is_chat_member(chat_id)
  );

CREATE POLICY "call_participants_select_authorized" ON public.call_participants
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid()) OR
    public.is_call_caller(call_id) OR
    public.is_call_participant(call_id)
  );

CREATE POLICY "call_outbox_service_role" ON public.call_outbox
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- Revoke all direct client mutations
REVOKE ALL ON public.calls FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.call_participants FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.call_outbox FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.calls TO authenticated;
GRANT SELECT ON public.call_participants TO authenticated;
GRANT ALL ON public.calls TO service_role;
GRANT ALL ON public.call_participants TO service_role;
GRANT ALL ON public.call_outbox TO service_role;

-- ------------------------------------------------------------------------------
-- 4. REALTIME REPLICATION
-- ------------------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE public.calls;
ALTER PUBLICATION supabase_realtime ADD TABLE public.call_participants;

-- ------------------------------------------------------------------------------
-- 5. STANDARDIZED ATOMIC RPCS (STRICT LOCK ORDER: CALLS -> PARTICIPANTS)
-- ------------------------------------------------------------------------------

-- RPC 1: initiate_call
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
  v_existing_call_id uuid;
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

  -- Concurrency check: Reject if active call already exists in this chat
  SELECT id INTO v_existing_call_id
  FROM public.calls
  WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
  LIMIT 1;

  IF v_existing_call_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_in_progress',
      'existing_call_id', v_existing_call_id
    );
  END IF;

  v_room_id := gen_random_uuid()::text;

  -- 2. Insert call record
  BEGIN
    INSERT INTO public.calls (
      chat_id, caller_id, call_type, is_group, status, room_id, started_at
    ) VALUES (
      p_chat_id, v_caller_id, p_call_type, v_is_group, 'ringing', v_room_id, clock_timestamp()
    ) RETURNING id INTO v_new_call_id;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT id INTO v_existing_call_id
      FROM public.calls
      WHERE chat_id = p_chat_id AND status IN ('ringing', 'ongoing')
      LIMIT 1;

      RETURN jsonb_build_object(
        'success', false,
        'error', 'call_in_progress',
        'existing_call_id', v_existing_call_id
      );
  END;

  -- 3. Insert participants
  INSERT INTO public.call_participants (call_id, user_id, status, joined_at)
  VALUES (v_new_call_id, v_caller_id, 'accepted', clock_timestamp());

  INSERT INTO public.call_participants (call_id, user_id, status)
  SELECT v_new_call_id, unnest(p_invitee_ids), 'invited';

  SELECT phone_e164, coalesce(display_name, '') INTO v_caller_phone, v_caller_name
  FROM public.profiles
  WHERE id = v_caller_id;

  -- 4. Atomic Transactional Outbox Insert (Dedup Key: call_id || ':initiate')
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

-- RPC 2: accept_call (Lock order: 1. calls -> 2. call_participants)
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

  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  -- 2. Lock participant row SECOND
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user is not an invited participant of this call' USING errcode = '42501';
  END IF;

  -- 3. Validate states & Idempotency
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

  -- 4. Server-Authoritative Timeout check using wall-clock clock_timestamp() (Decision A1)
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

  -- 5. Perform state transition
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

-- RPC 3: reject_call (Lock order: 1. calls -> 2. call_participants)
CREATE OR REPLACE FUNCTION public.reject_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call record;
  v_participant record;
  v_remaining_count int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  -- 2. Lock participant row SECOND
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user is not a participant of this call' USING errcode = '42501';
  END IF;

  -- 3. Validate states & Idempotency
  IF v_participant.status = 'rejected' THEN
    RETURN jsonb_build_object('success', true, 'status', 'already_rejected');
  END IF;

  IF v_participant.status = 'accepted' THEN
    RAISE EXCEPTION 'Cannot reject an accepted call; use leave_call instead' USING errcode = '22023';
  END IF;

  IF v_participant.status != 'invited' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status_for_rejection', 'status', v_participant.status);
  END IF;

  -- 4. Perform state transition
  UPDATE public.call_participants
  SET status = 'rejected', updated_at = clock_timestamp()
  WHERE id = v_participant.id;

  SELECT count(*) INTO v_remaining_count
  FROM public.call_participants
  WHERE call_id = p_call_id 
    AND status IN ('invited', 'accepted') 
    AND user_id != v_call.caller_id;

  IF v_remaining_count = 0 AND v_call.status = 'ringing' THEN
    UPDATE public.calls
    SET status = 'rejected', ended_at = clock_timestamp(), updated_at = clock_timestamp()
    WHERE id = p_call_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'rejected');
END;
$$;

-- RPC 4: cancel_call (Lock order: 1. calls -> 2. call_participants)
CREATE OR REPLACE FUNCTION public.cancel_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_call record;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id AND caller_id = v_caller_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: caller mismatch or call not found' USING errcode = '42501';
  END IF;

  IF v_call.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', true, 'status', 'already_cancelled');
  END IF;

  IF v_call.status != 'ringing' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'cannot_cancel_active_or_ended_call',
      'status', v_call.status
    );
  END IF;

  -- 2. Lock invitee participant rows SECOND (deterministic order by user_id)
  PERFORM 1 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND status = 'invited' 
  ORDER BY user_id
  FOR UPDATE;

  -- 3. Perform state transitions
  UPDATE public.calls
  SET status = 'cancelled', ended_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE id = p_call_id;

  UPDATE public.call_participants
  SET status = 'cancelled', updated_at = clock_timestamp()
  WHERE call_id = p_call_id AND status = 'invited';

  -- 4. Atomic Outbox Insert (Dedup Key: call_id || ':cancel')
  INSERT INTO public.call_outbox (
    call_id, event_type, dedup_key, payload, status
  ) VALUES (
    p_call_id,
    'call_cancelled',
    p_call_id || ':cancel',
    jsonb_build_object('callId', p_call_id, 'chatId', v_call.chat_id, 'callerId', v_caller_id),
    'pending'
  )
  ON CONFLICT (dedup_key) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'status', 'cancelled');
END;
$$;

-- RPC 5: leave_call (Lock order: 1. calls -> 2. call_participants)
CREATE OR REPLACE FUNCTION public.leave_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call record;
  v_participant record;
  v_active_count int;
  v_pending_count int;
  v_duration int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  -- 2. Lock participant row SECOND
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user is not a participant of this call' USING errcode = '42501';
  END IF;

  IF v_participant.status = 'left' THEN
    RETURN jsonb_build_object('success', true, 'status', 'already_left');
  END IF;

  IF v_participant.status NOT IN ('accepted', 'invited') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_status_to_leave',
      'status', v_participant.status
    );
  END IF;

  -- 3. Perform participant state transition
  UPDATE public.call_participants
  SET status = 'left', left_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE id = v_participant.id;

  SELECT count(*) INTO v_active_count
  FROM public.call_participants
  WHERE call_id = p_call_id AND status = 'accepted';

  SELECT count(*) INTO v_pending_count
  FROM public.call_participants
  WHERE call_id = p_call_id AND status = 'invited';

  -- 4. Call termination logic (Decision A2)
  IF (v_call.is_group = false AND v_active_count < 2) OR 
     (v_call.is_group = true AND (v_active_count = 0 OR (v_active_count = 1 AND v_pending_count = 0))) THEN

    IF v_call.connected_at IS NOT NULL THEN
      v_duration := GREATEST(0, EXTRACT(epoch FROM (clock_timestamp() - v_call.connected_at))::int);
    END IF;

    UPDATE public.calls
    SET status = 'ended', ended_at = clock_timestamp(), duration_seconds = v_duration, updated_at = clock_timestamp()
    WHERE id = p_call_id AND status IN ('ringing', 'ongoing');

    UPDATE public.call_participants
    SET status = 'cancelled', updated_at = clock_timestamp()
    WHERE call_id = p_call_id AND status = 'invited';

    RETURN jsonb_build_object(
      'success', true,
      'status', 'ended',
      'duration_seconds', v_duration,
      'call_ended', true
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'left',
    'active_participants', v_active_count,
    'pending_invitations', v_pending_count,
    'call_ended', false
  );
END;
$$;

-- RPC 6: invite_to_call (Lock order: 1. calls -> 2. call_participants)
CREATE OR REPLACE FUNCTION public.invite_to_call(
  p_call_id uuid,
  p_invitee_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_call record;
  v_valid_count int;
  v_unique_count int;
  v_actually_invited uuid[];
  v_inviter_phone text;
  v_inviter_name text;
  v_batch_dedup text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  IF p_invitee_ids IS NULL OR cardinality(p_invitee_ids) = 0 THEN
    RAISE EXCEPTION 'At least one invitee is required' USING errcode = '22023';
  END IF;

  IF NULL = ANY(p_invitee_ids) THEN
    RAISE EXCEPTION 'Invitee list must not contain NULL elements' USING errcode = '22023';
  END IF;

  IF v_user_id = ANY(p_invitee_ids) THEN
    RAISE EXCEPTION 'Caller cannot invite themselves' USING errcode = '22023';
  END IF;

  SELECT count(DISTINCT x) INTO v_unique_count FROM unnest(p_invitee_ids) AS x;
  IF v_unique_count != cardinality(p_invitee_ids) THEN
    RAISE EXCEPTION 'Duplicate invitees are not allowed' USING errcode = '22023';
  END IF;

  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  IF v_call.status NOT IN ('ringing', 'ongoing') THEN
    RAISE EXCEPTION 'Cannot invite to a terminated call' USING errcode = '22023';
  END IF;

  -- 2. Lock caller's participant row SECOND
  IF NOT EXISTS (
    SELECT 1 FROM public.call_participants
    WHERE call_id = p_call_id AND user_id = v_user_id AND status = 'accepted'
    FOR UPDATE
  ) THEN
    RAISE EXCEPTION 'Only active accepted participants can invite others' USING errcode = '42501';
  END IF;

  -- Validate chat membership
  SELECT count(DISTINCT user_id) INTO v_valid_count
  FROM public.chat_members
  WHERE chat_id = v_call.chat_id AND user_id = ANY(p_invitee_ids);

  IF v_valid_count != cardinality(p_invitee_ids) THEN
    RAISE EXCEPTION 'All invitees must be active members of the chat' USING errcode = '42501';
  END IF;

  -- 3. Insert only NEW participants; capture genuine insertions via CTE (Decision A4)
  WITH inserted_rows AS (
    INSERT INTO public.call_participants (call_id, user_id, status)
    SELECT p_call_id, unnest(p_invitee_ids), 'invited'
    ON CONFLICT (call_id, user_id) DO NOTHING
    RETURNING user_id
  )
  SELECT coalesce(array_agg(user_id), '{}'::uuid[]) INTO v_actually_invited
  FROM inserted_rows;

  -- 4. If genuinely new participants were added, dispatch Transactional Outbox event
  IF cardinality(v_actually_invited) > 0 THEN
    UPDATE public.calls 
    SET is_group = true, updated_at = clock_timestamp() 
    WHERE id = p_call_id;

    SELECT phone_e164, coalesce(display_name, '') INTO v_inviter_phone, v_inviter_name
    FROM public.profiles
    WHERE id = v_user_id;

    v_batch_dedup := p_call_id || ':invite:' || md5(array_to_string(v_actually_invited, ','));

    INSERT INTO public.call_outbox (
      call_id, event_type, dedup_key, payload, status
    ) VALUES (
      p_call_id,
      'call_invitation',
      v_batch_dedup,
      jsonb_build_object(
        'callId', p_call_id,
        'chatId', v_call.chat_id,
        'callerId', v_user_id,
        'callerName', coalesce(nullif(v_inviter_name, ''), v_inviter_phone, 'Caller'),
        'callType', v_call.call_type,
        'inviteeIds', v_actually_invited,
        'isMidCall', true
      ),
      'pending'
    )
    ON CONFLICT (dedup_key) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'call_id', p_call_id,
    'newly_invited_count', cardinality(v_actually_invited)
  );
END;
$$;

-- RPC 7: rejoin_call (Lock order: 1. calls -> 2. call_participants)
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

  -- 1. Lock call row FIRST
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

  -- 2. Lock participant row SECOND
  SELECT * INTO v_participant 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND user_id = v_user_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: user was never an authorized participant of this call' USING errcode = '42501';
  END IF;

  -- 3. Rejoining is permitted strictly from 'left' status (Decision A4)
  IF v_participant.status != 'left' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_status_for_rejoin',
      'current_status', v_participant.status
    );
  END IF;

  -- 4. Mutate state
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

-- RPC 8: timeout_call (Lock order: 1. calls -> 2. call_participants)
CREATE OR REPLACE FUNCTION public.timeout_call(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_call record;
BEGIN
  -- 1. Lock call row FIRST
  SELECT * INTO v_call 
  FROM public.calls 
  WHERE id = p_call_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call not found' USING errcode = 'P0002';
  END IF;

  IF v_call.status = 'missed' THEN
    RETURN jsonb_build_object('success', true, 'status', 'already_missed');
  END IF;

  IF v_call.status != 'ringing' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'call_not_ringing',
      'status', v_call.status
    );
  END IF;

  -- Wall-clock check
  IF clock_timestamp() < v_call.started_at + interval '45 seconds' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'timeout_window_not_elapsed',
      'remaining_seconds', EXTRACT(epoch FROM ((v_call.started_at + interval '45 seconds') - clock_timestamp()))::int
    );
  END IF;

  -- 2. Lock invitees SECOND (deterministic order by user_id)
  PERFORM 1 
  FROM public.call_participants 
  WHERE call_id = p_call_id AND status = 'invited' 
  ORDER BY user_id
  FOR UPDATE;

  -- 3. Mutate states
  UPDATE public.calls
  SET status = 'missed', ended_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE id = p_call_id;

  UPDATE public.call_participants
  SET status = 'missed', updated_at = clock_timestamp()
  WHERE call_id = p_call_id AND status = 'invited';

  RETURN jsonb_build_object('success', true, 'status', 'missed');
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. WORKER FUNCTIONS (SERVICE_ROLE ONLY)
-- ------------------------------------------------------------------------------

-- Worker Claiming Function: Recovers abandoned leases and claims pending events
CREATE OR REPLACE FUNCTION public.claim_call_outbox_events(
  p_worker_id text,
  p_batch_size integer DEFAULT 10,
  p_lease_duration_seconds integer DEFAULT 30
)
RETURNS SETOF public.call_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH eligible AS (
    SELECT id
    FROM public.call_outbox
    WHERE (
      (status = 'pending' AND retry_count < max_retries)
      OR
      (status = 'processing' AND locked_until < clock_timestamp() AND retry_count < max_retries)
      OR
      (status = 'failed' AND retry_count < max_retries AND updated_at + (power(2, retry_count) * interval '5 seconds') <= clock_timestamp())
    )
    ORDER BY created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.call_outbox o
  SET status = 'processing',
      locked_by = p_worker_id,
      locked_until = clock_timestamp() + (p_lease_duration_seconds || ' seconds')::interval,
      retry_count = o.retry_count + 1,
      updated_at = clock_timestamp()
  FROM eligible
  WHERE o.id = eligible.id
  RETURNING o.*;
END;
$$;

-- Automated Server-Side Timeout Processing Function
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

-- ------------------------------------------------------------------------------
-- 7. FUNCTION EXECUTION GRANTS
-- ------------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.initiate_call(uuid, text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.initiate_call(uuid, text, uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.accept_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_call(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.reject_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_call(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_call(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.leave_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_call(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.invite_to_call(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_to_call(uuid, uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.rejoin_call(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rejoin_call(uuid) TO authenticated;

-- timeout_call and worker functions are restricted strictly to service_role!
REVOKE ALL ON FUNCTION public.timeout_call(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.timeout_call(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.claim_call_outbox_events(text, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_call_outbox_events(text, integer, integer) TO service_role;

REVOKE ALL ON FUNCTION public.process_call_timeouts(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_call_timeouts(integer) TO service_role;
