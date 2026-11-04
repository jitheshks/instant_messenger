-- Real Database Integration and Concurrency Test Harness
-- Target: Local Supabase PostgreSQL 17 Container

BEGIN;

-- 1. Create Test Users & Profiles
DO $$
DECLARE
  v_user1 uuid := '11111111-1111-4111-8111-111111111111';
  v_user2 uuid := '22222222-2222-4222-8222-222222222222';
  v_user3 uuid := '33333333-3333-4333-8333-333333333333';
  v_outsider uuid := '99999999-9999-4999-8999-999999999999';
  v_direct_chat uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_group_chat uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
BEGIN
  -- Insert auth users
  INSERT INTO auth.users (id, email, role, aud)
  VALUES 
    (v_user1, 'user1@test.com', 'authenticated', 'authenticated'),
    (v_user2, 'user2@test.com', 'authenticated', 'authenticated'),
    (v_user3, 'user3@test.com', 'authenticated', 'authenticated'),
    (v_outsider, 'outsider@test.com', 'authenticated', 'authenticated')
  ON CONFLICT (id) DO NOTHING;

  -- Insert profiles
  INSERT INTO public.profiles (id, phone_e164, display_name)
  VALUES 
    (v_user1, '+1111111111', 'User One'),
    (v_user2, '+2222222222', 'User Two'),
    (v_user3, '+3333333333', 'User Three'),
    (v_outsider, '+9999999999', 'Outsider')
  ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

  -- Create direct chat
  INSERT INTO public.chats (id, type, created_by)
  VALUES (v_direct_chat, 'direct', v_user1)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES 
    (v_direct_chat, v_user1, 'member'),
    (v_direct_chat, v_user2, 'member')
  ON CONFLICT (chat_id, user_id) DO NOTHING;

  -- Create group chat
  INSERT INTO public.chats (id, type, title, created_by)
  VALUES (v_group_chat, 'group', 'Test Group', v_user1)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES 
    (v_group_chat, v_user1, 'admin'),
    (v_group_chat, v_user2, 'member'),
    (v_group_chat, v_user3, 'member')
  ON CONFLICT (chat_id, user_id) DO NOTHING;
END $$;

COMMIT;

-- ------------------------------------------------------------------------------
-- TEST 1: RLS Direct Mutation Protection
-- ------------------------------------------------------------------------------
\echo '=== TEST 1: RLS Direct Mutation Protection ==='
SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

DO $$
BEGIN
  -- Attempt direct INSERT into public.calls (MUST FAIL with 42501 permission denied)
  BEGIN
    INSERT INTO public.calls (chat_id, caller_id, call_type, status, room_id)
    VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'audio', 'ringing', 'hack-room');
    RAISE EXCEPTION 'TEST FAILED: direct INSERT into calls was not blocked!';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'SUCCESS: Direct INSERT into calls blocked by permission revoke';
  END;

  -- Attempt direct INSERT into public.call_participants (MUST FAIL)
  BEGIN
    INSERT INTO public.call_participants (call_id, user_id, status)
    VALUES ('550e8400-e29b-41d4-a716-446655440000', '11111111-1111-4111-8111-111111111111', 'accepted');
    RAISE EXCEPTION 'TEST FAILED: direct INSERT into call_participants was not blocked!';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'SUCCESS: Direct INSERT into call_participants blocked by permission revoke';
  END;

  -- Attempt direct INSERT into public.call_outbox (MUST FAIL)
  BEGIN
    INSERT INTO public.call_outbox (call_id, event_type, dedup_key, payload)
    VALUES ('550e8400-e29b-41d4-a716-446655440000', 'call_invitation', 'hack-key', '{}'::jsonb);
    RAISE EXCEPTION 'TEST FAILED: direct INSERT into call_outbox was not blocked!';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'SUCCESS: Direct INSERT into call_outbox blocked by permission revoke';
  END;
END $$;

RESET ROLE;

-- ------------------------------------------------------------------------------
-- TEST 2: initiate_call RPC, Outbox Creation & Concurrent Initiation Conflict
-- ------------------------------------------------------------------------------
\echo '=== TEST 2: initiate_call RPC & Conflict Detection ==='
SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

SELECT public.initiate_call(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'video',
  ARRAY['22222222-2222-4222-8222-222222222222'::uuid]
) AS call_initiation_result;

-- Concurrent call attempt in same direct chat by User 2 (MUST return call_in_progress)
SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

SELECT public.initiate_call(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'audio',
  ARRAY['11111111-1111-4111-8111-111111111111'::uuid]
) AS concurrent_call_result;

RESET ROLE;

-- Verify Database State after initiation
SELECT id, chat_id, caller_id, call_type, is_group, status, room_id 
FROM public.calls 
WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

SELECT call_id, user_id, status 
FROM public.call_participants 
WHERE call_id = (SELECT id FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

SELECT call_id, event_type, dedup_key, status, payload 
FROM public.call_outbox 
WHERE call_id = (SELECT id FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

-- ------------------------------------------------------------------------------
-- TEST 3: accept_call RPC, Idempotency & RLS Read Isolation
-- ------------------------------------------------------------------------------
\echo '=== TEST 3: accept_call RPC & RLS Read Isolation ==='
-- User 2 accepts the incoming call
SET ROLE authenticated;
SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

SELECT public.accept_call(
  (SELECT id FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
) AS accept_call_result;

-- Idempotent repeat accept (MUST succeed and return room_id)
SELECT public.accept_call(
  (SELECT id FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
) AS repeat_accept_result;

-- RLS Read Verification: User 2 can see call and participant rows
SELECT count(*) as user2_visible_calls 
FROM public.calls 
WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

-- RLS Read Verification: Outsider CANNOT see call rows
SET request.jwt.claim.sub = '99999999-9999-4999-8999-999999999999';

SELECT count(*) as outsider_visible_calls 
FROM public.calls 
WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

RESET ROLE;

-- ------------------------------------------------------------------------------
-- TEST 4: leave_call RPC & 1-on-1 Call Auto-Termination (Decision A2)
-- ------------------------------------------------------------------------------
\echo '=== TEST 4: leave_call RPC & Termination ==='
-- User 2 leaves the call
SET ROLE authenticated;
SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

SELECT public.leave_call(
  (SELECT id FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
) AS leave_call_result;

RESET ROLE;

-- Verify Call ended and duration recorded
SELECT id, status, started_at, connected_at, ended_at, duration_seconds 
FROM public.calls 
WHERE chat_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

-- ------------------------------------------------------------------------------
-- TEST 5: cancel_call RPC & Outbox Event Generation
-- ------------------------------------------------------------------------------
\echo '=== TEST 5: cancel_call RPC ==='
-- User 1 initiates a new call in the group chat
SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

SELECT public.initiate_call(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'audio',
  ARRAY['22222222-2222-4222-8222-222222222222'::uuid, '33333333-3333-4333-8333-333333333333'::uuid]
) AS group_initiation_result;

-- User 1 cancels the call before anyone answers
SELECT public.cancel_call(
  (SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
) AS cancel_call_result;

RESET ROLE;

-- Verify Call and participants status is 'cancelled' and cancel outbox event was created
SELECT id, status FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
SELECT user_id, status FROM public.call_participants WHERE call_id = (SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
SELECT event_type, dedup_key, status FROM public.call_outbox WHERE call_id = (SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

-- ------------------------------------------------------------------------------
-- TEST 6: Group Call Expansion (invite_to_call) & Rejoin (rejoin_call)
-- ------------------------------------------------------------------------------
\echo '=== TEST 6: invite_to_call & rejoin_call ==='
-- Cleanup group call for clean test
DELETE FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

-- User 1 initiates group call with User 2
SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

SELECT public.initiate_call(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'video',
  ARRAY['22222222-2222-4222-8222-222222222222'::uuid]
);

-- User 2 accepts
SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
SELECT public.accept_call((SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));

-- User 2 invites User 3 mid-call
SELECT public.invite_to_call(
  (SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  ARRAY['33333333-3333-4333-8333-333333333333'::uuid]
) AS invite_result;

-- User 2 leaves the call
SELECT public.leave_call((SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));

-- Call remains active because User 1 is accepted and User 3 is pending (Decision A2)!
RESET ROLE;
SELECT id, status FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

-- User 2 rejoins the call from 'left' status
SET ROLE authenticated;
SET request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
SELECT public.rejoin_call((SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')) AS rejoin_result;
RESET ROLE;

SELECT user_id, status FROM public.call_participants WHERE call_id = (SELECT id FROM public.calls WHERE chat_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

-- ------------------------------------------------------------------------------
-- TEST 7: Outbox Claiming & Lease Expiry (claim_call_outbox_events)
-- ------------------------------------------------------------------------------
\echo '=== TEST 7: claim_call_outbox_events & Lease Expiration ==='
SET ROLE service_role;

-- Claim pending outbox events with 2-second lease
SELECT id, event_type, status, locked_by, locked_until 
FROM public.claim_call_outbox_events('worker_test_1', 10, 2);

-- Immediate second claim while lease is active (MUST return 0 rows because locked_until > clock_timestamp())
SELECT count(*) as locked_events_skipped 
FROM public.claim_call_outbox_events('worker_test_2', 10, 2);

-- Wait 2.5 seconds for lease to expire
SELECT pg_sleep(2.5);

-- Third claim after lease expiry (MUST successfully recover abandoned events!)
SELECT id, event_type, status, locked_by, retry_count 
FROM public.claim_call_outbox_events('worker_test_recovery', 10, 30);

RESET ROLE;

-- ------------------------------------------------------------------------------
-- TEST 8: Server-Side Timeout Processing (process_call_timeouts)
-- ------------------------------------------------------------------------------
\echo '=== TEST 8: process_call_timeouts ==='
-- Insert a test ringing call with started_at 50 seconds ago
DO $$
DECLARE
  v_stale_call uuid;
BEGIN
  INSERT INTO public.calls (chat_id, caller_id, call_type, status, room_id, started_at)
  VALUES (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '11111111-1111-4111-8111-111111111111',
    'audio',
    'ringing',
    gen_random_uuid()::text,
    clock_timestamp() - interval '50 seconds'
  ) RETURNING id INTO v_stale_call;

  INSERT INTO public.call_participants (call_id, user_id, status)
  VALUES (v_stale_call, '22222222-2222-4222-8222-222222222222', 'invited');
END $$;

SET ROLE service_role;
SELECT public.process_call_timeouts(25) AS timeout_processing_result;
RESET ROLE;

-- Verify the stale call transitioned to 'missed'
SELECT id, status, started_at, ended_at 
FROM public.calls 
WHERE status = 'missed';
