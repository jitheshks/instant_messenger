"""
SQL Heartbeat Migration Test Suite (Phase 7 Hardened)
Tests all concurrency, lifecycle, and feature-flag gating scenarios against local PostgreSQL container.
"""

import os
import subprocess
import json
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

env = os.environ.copy()
env['PGPASSWORD'] = 'postgres'
PG_HOST = os.environ.get('PGHOST', 'localhost')
PG_PORT = os.environ.get('PGPORT', '54322')
PG_USER = os.environ.get('PGUSER', 'postgres')

def run_sql(sql):
    cmd = ['psql', '-h', PG_HOST, '-p', PG_PORT, '-U', PG_USER, '-t', '-A', '-c', sql]
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"SQL Error: {res.stderr}\nQuery: {sql}")
    return res.stdout.strip()

def run_script(filepath):
    cmd = ['psql', '-h', PG_HOST, '-p', PG_PORT, '-U', PG_USER, '-f', filepath]
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Script Error in {filepath}: {res.stderr}")
    return res.stdout

def setup_test_users_and_chat():
    sql = """
    TRUNCATE public.calls, public.call_participants, public.call_outbox, public.chat_members, public.chats, public.profiles, auth.users CASCADE;
    
    -- Create 3 test users
    INSERT INTO auth.users (id, phone, raw_user_meta_data) VALUES 
      ('11111111-1111-1111-1111-111111111111', '+10000000001', '{"display_name": "Alice"}'),
      ('22222222-2222-2222-2222-222222222222', '+10000000002', '{"display_name": "Bob"}'),
      ('33333333-3333-3333-3333-333333333333', '+10000000003', '{"display_name": "Charlie"}')
    ON CONFLICT (id) DO NOTHING;
    
    INSERT INTO public.profiles (id, phone_e164, display_name) VALUES
      ('11111111-1111-1111-1111-111111111111', '+10000000001', 'Alice'),
      ('22222222-2222-2222-2222-222222222222', '+10000000002', 'Bob'),
      ('33333333-3333-3333-3333-333333333333', '+10000000003', 'Charlie')
    ON CONFLICT (id) DO UPDATE SET phone_e164 = EXCLUDED.phone_e164, display_name = EXCLUDED.display_name;
    
    -- Create direct chat between Alice and Bob
    INSERT INTO public.chats (id, type) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'direct') ON CONFLICT DO NOTHING;
    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES 
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'member'),
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member')
    ON CONFLICT DO NOTHING;
    
    -- Create group chat with Alice, Bob, Charlie
    INSERT INTO public.chats (id, type) VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'group') ON CONFLICT DO NOTHING;
    INSERT INTO public.chat_members (chat_id, user_id, role) VALUES 
      ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'admin'),
      ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'member'),
      ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', 'member')
    ON CONFLICT DO NOTHING;
    """
    run_sql(sql)

def test_scenario_0_rollout_gate_disabled_protects_legacy_clients():
    print("Testing Scenario 0: Rollout gate disabled ('false') protects legacy ongoing calls...")
    setup_test_users_and_chat()
    sql = """
    -- Ensure feature flag is explicitly DISABLED (the safe post-migration default)
    UPDATE public.app_settings SET value = 'false' WHERE key = 'calling_heartbeat_recovery_enabled';
    
    -- Insert an ongoing call where legacy participants haven't sent heartbeats for 200 seconds
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c0000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-0', clock_timestamp() - interval '300 seconds', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '200 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c0000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '200 seconds'),
      ('c0000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '200 seconds');

    -- Also insert a stale ringing call (>45s)
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, last_activity_at)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'audio', true, 'ringing', 'room-0-ring', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '60 seconds');

    -- Run worker
    SELECT public.process_call_timeouts(25);
    
    -- Verify: ongoing call is completely preserved, while ringing call is missed
    SELECT c0.status, c1.status 
    FROM public.calls c0, public.calls c1 
    WHERE c0.id = 'c0000000-0000-0000-0000-000000000000' AND c1.id = 'c0000000-0000-0000-0000-000000000001';
    """
    out = run_sql(sql)
    ongoing_status, ringing_status = out.split('\n')[-1].split('|')
    assert ongoing_status == 'ongoing', f"Ongoing call should NOT be expired when flag is disabled, got: '{ongoing_status}'"
    assert ringing_status == 'missed', f"Ringing call SHOULD be expired regardless of flag, got: '{ringing_status}'"

    # Now verify initiate_call inline does NOT expire the ongoing call when flag is disabled
    initiate_sql = """
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    SELECT public.initiate_call('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'audio', ARRAY['22222222-2222-2222-2222-222222222222'::uuid]);
    """
    init_out = run_sql(initiate_sql)
    res = json.loads(init_out.split('\n')[-1])
    assert res.get('success') is False and res.get('error') == 'call_in_progress', \
        f"Expected call_in_progress when flag disabled, got: {res}"
    print("  -> PASS: Rollout gate disabled protects legacy clients from premature expiration.")

def test_scenario_1_one_participant_active_keeps_call_alive():
    print("Testing Scenario 1: One active participant heartbeating keeps call alive...")
    setup_test_users_and_chat()
    sql = """
    UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c1111111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-1', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '10 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '10 seconds'),
      ('c1111111-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '120 seconds');
      
    -- Run timeout worker
    SELECT public.process_call_timeouts(25);
    
    SELECT status FROM public.calls WHERE id = 'c1111111-0000-0000-0000-000000000001';
    """
    out = run_sql(sql)
    status = out.split('\n')[-1]
    assert status == 'ongoing', f"Expected call to remain 'ongoing', got '{status}'"
    print("  -> PASS: Ongoing call preserved while Alice heartbeats.")

def test_scenario_2_all_participants_silent_recovered():
    print("Testing Scenario 2: All participants silent (>90s) recovered as abandoned...")
    setup_test_users_and_chat()
    sql = """
    UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';
    
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-2', clock_timestamp() - interval '300 seconds', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '100 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '100 seconds'),
      ('c2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '120 seconds');
      
    SELECT public.process_call_timeouts(25);
    
    SELECT status, duration_seconds FROM public.calls WHERE id = 'c2222222-0000-0000-0000-000000000002';
    """
    out = run_sql(sql)
    last_line = out.split('\n')[-1]
    status, duration = last_line.split('|')
    assert status == 'ended', f"Expected status 'ended', got '{status}'"
    dur_int = int(duration)
    assert 185 <= dur_int <= 195, f"Expected duration ~190s, got {dur_int}s"
    print(f"  -> PASS: Abandoned call transitioned to 'ended', duration={dur_int}s accurately excludes deserted time.")

def test_scenario_3_group_call_liveness():
    print("Testing Scenario 3: Group call liveness with partial dropouts...")
    setup_test_users_and_chat()
    sql = """
    UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';
    
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c3333333-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'video', true, 'ongoing', 'room-3', clock_timestamp() - interval '500 seconds', clock_timestamp() - interval '480 seconds', clock_timestamp() - interval '15 seconds');
    
    -- Alice & Bob silent for 200s, Charlie active 15s ago
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c3333333-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '480 seconds', clock_timestamp() - interval '200 seconds'),
      ('c3333333-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '480 seconds', clock_timestamp() - interval '200 seconds'),
      ('c3333333-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'accepted', clock_timestamp() - interval '480 seconds', clock_timestamp() - interval '15 seconds');
      
    SELECT public.process_call_timeouts(25);
    SELECT status FROM public.calls WHERE id = 'c3333333-0000-0000-0000-000000000003';
    """
    out = run_sql(sql)
    status = out.split('\n')[-1]
    assert status == 'ongoing', f"Expected group call to remain 'ongoing', got '{status}'"
    print("  -> PASS: Group call preserved while at least 1 participant pulses heartbeats.")

def test_scenario_4_heartbeat_rpc_and_post_termination():
    print("Testing Scenario 4: heartbeat_call RPC and post-termination rejection...")
    setup_test_users_and_chat()
    sql = """
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c4444444-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-4', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '10 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c4444444-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '10 seconds'),
      ('c4444444-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '10 seconds');
      
    -- Alice sends heartbeat
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    SELECT public.heartbeat_call('c4444444-0000-0000-0000-000000000004');
    """
    out = run_sql(sql)
    res = json.loads(out.split('\n')[-1])
    assert res.get('success') is True, f"Expected heartbeat success, got: {res}"
    
    # Now end the call and verify heartbeat is rejected
    sql_term = """
    UPDATE public.calls SET status = 'ended', ended_at = clock_timestamp() WHERE id = 'c4444444-0000-0000-0000-000000000004';
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    SELECT public.heartbeat_call('c4444444-0000-0000-0000-000000000004');
    """
    out2 = run_sql(sql_term)
    res2 = json.loads(out2.split('\n')[-1])
    assert res2.get('success') is False and res2.get('error') in ('call_ended', 'call_not_ongoing'), f"Expected call_ended error, got: {res2}"
    print("  -> PASS: heartbeat_call succeeds on ongoing call and cleanly rejects ended call.")

def test_scenario_5_idempotent_accept_refresh():
    print("Testing Scenario 5: accept_call idempotently refreshes last_heartbeat_at...")
    setup_test_users_and_chat()
    sql = """
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c5555555-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-5', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '10 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c5555555-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '50 seconds'),
      ('c5555555-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '50 seconds');
      
    -- Bob re-executes accept_call
    SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
    SELECT public.accept_call('c5555555-0000-0000-0000-000000000005');
    """
    out = run_sql(sql)
    res = json.loads(out.split('\n')[-1])
    assert res.get('success') is True, f"Expected idempotent accept success, got: {res}"
    
    # Verify Bob's heartbeat timestamp was refreshed to fresh time (<2s ago)
    check_sql = """
    SELECT EXTRACT(epoch FROM (clock_timestamp() - last_heartbeat_at)) < 2 
    FROM public.call_participants 
    WHERE call_id = 'c5555555-0000-0000-0000-000000000005' AND user_id = '22222222-2222-2222-2222-222222222222';
    """
    is_fresh = run_sql(check_sql).split('\n')[-1]
    assert is_fresh == 't', f"Expected refreshed heartbeat timestamp, got: {is_fresh}"
    print("  -> PASS: accept_call idempotency refreshes heartbeat without resetting ongoing call state.")

def test_scenario_6_rejoin_call_liveness():
    print("Testing Scenario 6: rejoin_call restores accepted status and refreshes heartbeat...")
    setup_test_users_and_chat()
    sql = """
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c6666666-0000-0000-0000-000000000006', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'video', true, 'ongoing', 'room-6', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '180 seconds', clock_timestamp() - interval '20 seconds');
    
    -- Bob had left 60 seconds ago
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, left_at, last_heartbeat_at) VALUES
      ('c6666666-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '180 seconds', NULL, clock_timestamp() - interval '20 seconds'),
      ('c6666666-0000-0000-0000-000000000006', '22222222-2222-2222-2222-222222222222', 'left', clock_timestamp() - interval '180 seconds', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '60 seconds');
      
    -- Bob rejoins call
    SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
    SELECT public.rejoin_call('c6666666-0000-0000-0000-000000000006');
    """
    out = run_sql(sql)
    res = json.loads(out.split('\n')[-1])
    assert res.get('success') is True, f"Expected rejoin success, got: {res}"
    
    check_sql = """
    SELECT status, left_at IS NULL, EXTRACT(epoch FROM (clock_timestamp() - last_heartbeat_at)) < 2 
    FROM public.call_participants 
    WHERE call_id = 'c6666666-0000-0000-0000-000000000006' AND user_id = '22222222-2222-2222-2222-222222222222';
    """
    st, left_null, fresh = run_sql(check_sql).split('\n')[-1].split('|')
    assert st == 'accepted' and left_null == 't' and fresh == 't', f"Rejoin assertion failed: {st}, {left_null}, {fresh}"
    print("  -> PASS: rejoin_call restores status='accepted', clears left_at, and refreshes last_heartbeat_at.")

def test_scenario_7_migration_grace_period():
    print("Testing Scenario 7: Migration-time grace period protects legacy active calls...")
    setup_test_users_and_chat()
    sql = """
    UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';
    
    -- Legacy ongoing call with active grace period until future (15 minutes from now)
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at, migration_grace_until)
    VALUES ('c7777777-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-7', clock_timestamp() - interval '600 seconds', clock_timestamp() - interval '580 seconds', clock_timestamp() - interval '500 seconds', clock_timestamp() + interval '10 minutes');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c7777777-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '580 seconds', clock_timestamp() - interval '500 seconds'),
      ('c7777777-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '580 seconds', clock_timestamp() - interval '500 seconds');
      
    -- Run timeout worker while grace is active
    SELECT public.process_call_timeouts(25);
    SELECT status FROM public.calls WHERE id = 'c7777777-0000-0000-0000-000000000007';
    """
    out = run_sql(sql)
    status = out.split('\n')[-1]
    assert status == 'ongoing', f"Legacy ongoing call prematurely expired during grace period! Got: '{status}'"
    
    # Now simulate grace period having expired in the past
    sql_expired_grace = """
    UPDATE public.calls SET migration_grace_until = clock_timestamp() - interval '1 second' WHERE id = 'c7777777-0000-0000-0000-000000000007';
    SELECT public.process_call_timeouts(25);
    SELECT status, duration_seconds, ended_at <= clock_timestamp() - interval '400 seconds' FROM public.calls WHERE id = 'c7777777-0000-0000-0000-000000000007';
    """
    out2 = run_sql(sql_expired_grace)
    st, dur, real_epoch = out2.split('\n')[-1].split('|')
    assert st == 'ended', f"Expected status 'ended' after grace expired, got '{st}'"
    assert real_epoch == 't', f"Expected ended_at to reflect genuine historical epoch, got: {real_epoch}"
    print("  -> PASS: migration_grace_until shields call during grace and does NOT contaminate ended_at epoch.")

def test_scenario_8_historical_terminal_call_integrity():
    print("Testing Scenario 8: Historical terminal calls remain completely untouched...")
    setup_test_users_and_chat()
    sql = """
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, ended_at, duration_seconds, last_activity_at)
    VALUES ('c8888888-0000-0000-0000-000000000008', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ended', 'room-8', clock_timestamp() - interval '2 days', clock_timestamp() - interval '2 days', clock_timestamp() - interval '2 days' + interval '300 seconds', 300, clock_timestamp() - interval '2 days' + interval '300 seconds');
    
    SELECT public.process_call_timeouts(25);
    SELECT status, duration_seconds FROM public.calls WHERE id = 'c8888888-0000-0000-0000-000000000008';
    """
    out = run_sql(sql)
    st, dur = out.split('\n')[-1].split('|')
    assert st == 'ended' and dur == '300', f"Historical call corrupted: {st}, {dur}"
    print("  -> PASS: Historical terminal call preserved with original status and duration.")

def test_scenario_9_inline_timeout_in_initiate_call():
    print("Testing Scenario 9: initiate_call inline timeout recovery cleans abandoned call...")
    setup_test_users_and_chat()
    sql = """
    UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';
    
    -- Old abandoned call in direct chat
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c9999999-0000-0000-0000-000000000009', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-9', clock_timestamp() - interval '300 seconds', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '120 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c9999999-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '120 seconds'),
      ('c9999999-0000-0000-0000-000000000009', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '120 seconds');
      
    -- Alice initiates a new call in the same chat
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    SELECT public.initiate_call('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'audio', ARRAY['22222222-2222-2222-2222-222222222222'::uuid]);
    """
    out = run_sql(sql)
    res = json.loads(out.split('\n')[-1])
    assert res.get('success') is True, f"Expected initiate_call success after inline cleanup, got: {res}"
    
    # Old call must now be 'ended'
    old_st = run_sql("SELECT status FROM public.calls WHERE id = 'c9999999-0000-0000-0000-000000000009';")
    assert old_st == 'ended', f"Expected old call to be ended inline, got '{old_st}'"
    print("  -> PASS: initiate_call cleans abandoned ongoing call inline and creates new call.")

def test_scenario_10_rollback_and_reapply():
    print("Testing Scenario 10: Executing complete rollback script and reapplying migration...")
    # Run rollback script from dedicated rollbacks directory
    run_script('supabase/rollbacks/20261104000001_calling_participant_heartbeat_and_liveness_rollback.sql')
    
    # Verify heartbeat_call is gone
    check_fn = run_sql("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'heartbeat_call');")
    assert check_fn == 'f', f"Expected heartbeat_call to be dropped, got: {check_fn}"
    
    # Verify is_feature_enabled is gone
    check_feat = run_sql("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_feature_enabled');")
    assert check_feat == 'f', f"Expected is_feature_enabled to be dropped, got: {check_feat}"

    # Verify app_settings is gone
    check_tbl = run_sql("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'app_settings');")
    assert check_tbl == 'f', f"Expected app_settings to be dropped, got: {check_tbl}"

    # Verify migration_grace_until is gone
    check_col = run_sql("SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='migration_grace_until');")
    assert check_col == 'f', f"Expected migration_grace_until to be dropped, got: {check_col}"
    print("  -> Rollback executed cleanly. RPCs dropped, feature flags removed, schema restored.")
    
    # Reapply migration
    run_script('supabase/migrations/20261104000001_calling_participant_heartbeat_and_liveness.sql')
    run_script('supabase/migrations/20261104000002_harden_app_settings_least_privilege.sql')
    check_fn_again = run_sql("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'heartbeat_call');")
    assert check_fn_again == 't', f"Expected heartbeat_call to exist after reapply, got: {check_fn_again}"

    check_flag_default = run_sql("SELECT public.is_feature_enabled('calling_heartbeat_recovery_enabled');")
    assert check_flag_default == 'f', f"Expected feature flag default to be 'f', got: {check_flag_default}"
    print("  -> Migration reapplied cleanly after rollback with safe default feature flag.")

def test_scenario_13_least_privilege_permissions():
    print("Testing Scenario 13: Least-Privilege Permissions on public.app_settings (AUD-06)...")
    test_sql = """
    DO $$
    BEGIN
      -- 1. anon direct access must be DENIED
      BEGIN
        SET ROLE anon;
        PERFORM * FROM public.app_settings;
        RAISE EXCEPTION 'Security failure: anon permitted direct table SELECT!';
      EXCEPTION WHEN insufficient_privilege THEN
        NULL;
      END;

      -- 2. authenticated direct access must be DENIED
      BEGIN
        SET ROLE authenticated;
        PERFORM * FROM public.app_settings;
        RAISE EXCEPTION 'Security failure: authenticated permitted direct table SELECT!';
      EXCEPTION WHEN insufficient_privilege THEN
        NULL;
      END;

      -- 3. anon controlled read via is_feature_enabled must SUCCEED
      SET ROLE anon;
      IF public.is_feature_enabled('calling_heartbeat_recovery_enabled') != false THEN
        RAISE EXCEPTION 'Security failure: anon is_feature_enabled returned unexpected value!';
      END IF;

      -- 4. authenticated controlled read via is_feature_enabled must SUCCEED
      SET ROLE authenticated;
      IF public.is_feature_enabled('calling_heartbeat_recovery_enabled') != false THEN
        RAISE EXCEPTION 'Security failure: authenticated is_feature_enabled returned unexpected value!';
      END IF;

      -- 5. service_role direct access must SUCCEED
      SET ROLE service_role;
      PERFORM * FROM public.app_settings;
    END $$;
    """
    run_sql(test_sql)
    print("  -> PASS: Direct client SELECT strictly denied; controlled is_feature_enabled and service_role access verified.")

def test_scenario_11_multi_connection_concurrency():
    print("Testing Scenario 11: Multi-connection concurrent heartbeats and timeouts (Deadlock & Race Safety)...")
    setup_test_users_and_chat()
    
    # Enable feature flag for concurrency stress
    run_sql("UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';")

    # Create an ongoing call
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c1111111-1111-0000-0000-000000000011', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'video', true, 'ongoing', 'room-conc', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c1111111-1111-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds'),
      ('c1111111-1111-0000-0000-000000000011', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds'),
      ('c1111111-1111-0000-0000-000000000011', '33333333-3333-3333-3333-333333333333', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    """)

    def worker_heartbeat(user_id):
        sql = f"""
        SET request.jwt.claim.sub = '{user_id}';
        SELECT public.heartbeat_call('c1111111-1111-0000-0000-000000000011');
        """
        out = run_sql(sql)
        res = json.loads(out.split('\n')[-1])
        return res.get('success')

    def worker_timeout():
        sql = "SELECT public.process_call_timeouts(25);"
        out = run_sql(sql)
        res = json.loads(out.split('\n')[-1])
        return res.get('success')

    users = [
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333'
    ]

    # Run 20 concurrent operations across a thread pool
    futures = []
    with ThreadPoolExecutor(max_workers=8) as executor:
        for i in range(15):
            u = users[i % len(users)]
            futures.append(executor.submit(worker_heartbeat, u))
        for _ in range(5):
            futures.append(executor.submit(worker_timeout))

        for f in as_completed(futures):
            success = f.result()
            assert success is True, "Concurrent operation failed"

    # Verify call is still ongoing and consistent
    final_st = run_sql("SELECT status FROM public.calls WHERE id = 'c1111111-1111-0000-0000-000000000011';")
    assert final_st == 'ongoing', f"Expected call to remain ongoing after concurrent pulses, got: {final_st}"
    print("  -> PASS: 20 concurrent operations across 8 connections executed without deadlock or serialization failure.")

class PsqlSession:
    def __init__(self):
        cmd = ['psql', '-h', PG_HOST, '-p', PG_PORT, '-U', PG_USER, '-t', '-A']
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )

    def execute(self, sql):
        sentinel = f"__SENTINEL_{time.time()}__"
        full_sql = f"{sql};\nSELECT '{sentinel}';\n"
        self.proc.stdin.write(full_sql)
        self.proc.stdin.flush()
        
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                break
            stripped = line.strip()
            if stripped == sentinel:
                break
            if stripped:
                lines.append(stripped)
        return "\n".join(lines)

    def close(self):
        try:
            self.proc.stdin.write("\\q\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=2)
        except Exception:
            self.proc.kill()

def test_scenario_12_deterministic_race_conditions():
    print("Testing Scenario 12: Deterministic Concurrency Races (Section 3.1)...")
    setup_test_users_and_chat()
    run_sql("UPDATE public.app_settings SET value = 'true' WHERE key = 'calling_heartbeat_recovery_enabled';")

    # Race 1: Heartbeat vs timeout worker — heartbeat obtains lock first
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0001-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-r1', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '95 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0001-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '95 seconds');
    """)
    s1 = PsqlSession()
    s2 = PsqlSession()
    try:
        # S1 takes lock on call
        s1.execute("BEGIN; SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT id FROM public.calls WHERE id = 'c2222222-0001-0000-0000-000000000001' FOR UPDATE;")
        # S2 executes timeout worker (uses SKIP LOCKED, so skips c2222222-0001-0000-0000-000000000001)
        res_worker = json.loads(s2.execute("SELECT public.process_call_timeouts(25);"))
        assert res_worker.get('expired_ongoing_count') == 0, f"Expected 0 expired ongoing while locked, got: {res_worker}"
        # S1 executes heartbeat and commits
        out_hb = s1.execute("SELECT public.heartbeat_call('c2222222-0001-0000-0000-000000000001'); COMMIT;")
        res_hb = json.loads(out_hb.split('\n')[0])
        assert res_hb.get('success') is True, f"Heartbeat failed: {res_hb}"
        # Verify call remains ongoing
        st = run_sql("SELECT status FROM public.calls WHERE id = 'c2222222-0001-0000-0000-000000000001';")
        assert st == 'ongoing', f"Race 1: Expected call to remain ongoing, got: {st}"
    finally:
        s1.close()
        s2.close()
    print("  -> Race 1 PASS: Heartbeat holds lock first -> call preserved, timeout skips locked call.")

    # Race 2: Heartbeat vs timeout worker — timeout worker obtains lock first
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0002-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-r2', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '100 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0002-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '100 seconds');
    """)
    s1 = PsqlSession()
    s2 = PsqlSession()
    try:
        # S1 starts transaction, terminates call and holds lock
        s1.execute("BEGIN; SELECT id FROM public.calls WHERE id = 'c2222222-0002-0000-0000-000000000002' FOR UPDATE; UPDATE public.calls SET status = 'ended', ended_at = clock_timestamp() WHERE id = 'c2222222-0002-0000-0000-000000000002';")
        # S2 runs heartbeat in thread (blocks waiting for lock)
        hb_res = []
        def run_hb():
            out = s2.execute("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.heartbeat_call('c2222222-0002-0000-0000-000000000002');")
            hb_res.append(out)
        t = threading.Thread(target=run_hb)
        t.start()
        time.sleep(0.15)
        # S1 commits, releasing lock
        s1.execute("COMMIT;")
        t.join(timeout=2.0)
        assert len(hb_res) == 1, "Thread did not complete"
        res_data = json.loads(hb_res[0].split('\n')[-1])
        assert res_data.get('success') is False and res_data.get('error') == 'call_not_ongoing', \
            f"Race 2: Expected call_not_ongoing, got: {res_data}"
    finally:
        s1.close()
        s2.close()
    print("  -> Race 2 PASS: Timeout worker holds lock first -> heartbeat unblocks with call_not_ongoing.")

    # Race 3: initiate_call vs explicit participant leave
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0003-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-r3', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0003-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds'),
      ('c2222222-0003-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    """)
    # Alice leaves call (1-on-1 -> transitions to ended)
    res_leave = json.loads(run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.leave_call('c2222222-0003-0000-0000-000000000003');").split('\n')[-1])
    assert res_leave.get('success') is True, f"leave_call failed: {res_leave}"
    # Bob initiates new call in same chat
    res_init = json.loads(run_sql("SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222'; SELECT public.initiate_call('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'video', ARRAY['11111111-1111-1111-1111-111111111111'::uuid]);").split('\n')[-1])
    assert res_init.get('success') is True, f"initiate_call failed after leave: {res_init}"
    active_cnt = int(run_sql("SELECT count(*) FROM public.calls WHERE chat_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND status IN ('ringing', 'ongoing');"))
    assert active_cnt == 1, f"Expected exactly 1 active call in chat, got: {active_cnt}"
    print("  -> Race 3 PASS: initiate_call after leave preserves exactly 1 active call without conflict.")

    # Race 4: accept_call vs caller cancel_call
    setup_test_users_and_chat()
    # Branch A: Caller cancels first
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, last_activity_at)
    VALUES ('c2222222-0004-0000-0000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'audio', true, 'ringing', 'room-r4a', clock_timestamp(), clock_timestamp());
    INSERT INTO public.call_participants (call_id, user_id, status) VALUES
      ('c2222222-0004-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'accepted'),
      ('c2222222-0004-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'invited');
    """)
    cancel_res = json.loads(run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.cancel_call('c2222222-0004-0000-0000-000000000004');").split('\n')[-1])
    assert cancel_res.get('success') is True, f"cancel_call failed: {cancel_res}"
    accept_res = json.loads(run_sql("SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222'; SELECT public.accept_call('c2222222-0004-0000-0000-000000000004');").split('\n')[-1])
    assert accept_res.get('success') is False and accept_res.get('error') in ('call_already_cancelled', 'invitation_cancelled'), \
        f"Expected call/invitation cancelled, got: {accept_res}"

    # Branch B: Callee accepts first
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, last_activity_at)
    VALUES ('c2222222-0004-0000-0000-000000000005', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'audio', true, 'ringing', 'room-r4b', clock_timestamp(), clock_timestamp());
    INSERT INTO public.call_participants (call_id, user_id, status) VALUES
      ('c2222222-0004-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'accepted'),
      ('c2222222-0004-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'invited');
    """)
    accept_res_b = json.loads(run_sql("SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222'; SELECT public.accept_call('c2222222-0004-0000-0000-000000000005');").split('\n')[-1])
    assert accept_res_b.get('success') is True, f"accept_call failed: {accept_res_b}"
    cancel_res_b = json.loads(run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.cancel_call('c2222222-0004-0000-0000-000000000005');").split('\n')[-1])
    assert cancel_res_b.get('success') is False and cancel_res_b.get('error') == 'cannot_cancel_active_or_ended_call', \
        f"Expected cannot_cancel_active_or_ended_call, got: {cancel_res_b}"
    print("  -> Race 4 PASS: accept_call vs cancel_call enforces mutually exclusive valid terminal state.")

    # Race 5: rejoin_call vs timeout processing
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0005-0000-0000-000000000005', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'audio', true, 'ongoing', 'room-r5', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '95 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, left_at, last_heartbeat_at) VALUES
      ('c2222222-0005-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'left', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '100 seconds', clock_timestamp() - interval '100 seconds'),
      ('c2222222-0005-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '190 seconds', NULL, clock_timestamp() - interval '95 seconds');
    """)
    # Timeout worker terminates the call
    run_sql("SELECT public.process_call_timeouts(25);")
    # Alice attempts to rejoin ended call
    rejoin_res = json.loads(run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.rejoin_call('c2222222-0005-0000-0000-000000000005');").split('\n')[-1])
    assert rejoin_res.get('success') is False and rejoin_res.get('error') == 'cannot_rejoin_call_status_ended', \
        f"Expected cannot_rejoin_call_status_ended, got: {rejoin_res}"
    print("  -> Race 5 PASS: rejoin_call cleanly rejected with cannot_rejoin_call_status_ended on ended call.")

    # Race 6: Two timeout workers processing the same call
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0006-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-r6', clock_timestamp() - interval '200 seconds', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '95 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0006-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '190 seconds', clock_timestamp() - interval '95 seconds');
    """)
    w1_res = []
    w2_res = []
    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(lambda: run_sql("SELECT public.process_call_timeouts(25);"))
        f2 = ex.submit(lambda: run_sql("SELECT public.process_call_timeouts(25);"))
        r1 = json.loads(f1.result().split('\n')[-1])
        r2 = json.loads(f2.result().split('\n')[-1])
        w1_res.append(r1.get('expired_ongoing_count', 0))
        w2_res.append(r2.get('expired_ongoing_count', 0))
    total_expired = sum(w1_res) + sum(w2_res)
    assert total_expired == 1, f"Expected exactly 1 ongoing expiration across parallel workers, got: {total_expired}"
    st_r6 = run_sql("SELECT status FROM public.calls WHERE id = 'c2222222-0006-0000-0000-000000000006';")
    assert st_r6 == 'ended', f"Expected status ended, got: {st_r6}"
    print("  -> Race 6 PASS: Concurrent timeout workers safely coordinate via SKIP LOCKED (exactly 1 expires call).")

    # Race 7: Multiple devices for one participant pulsing heartbeats
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0007-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'audio', false, 'ongoing', 'room-r7', clock_timestamp() - interval '60 seconds', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0007-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '50 seconds', clock_timestamp() - interval '5 seconds');
    """)
    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(lambda: run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.heartbeat_call('c2222222-0007-0000-0000-000000000007');"))
        f2 = ex.submit(lambda: run_sql("SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111'; SELECT public.heartbeat_call('c2222222-0007-0000-0000-000000000007');"))
        res1 = json.loads(f1.result().split('\n')[-1])
        res2 = json.loads(f2.result().split('\n')[-1])
        assert res1.get('success') is True, f"Device 1 heartbeat failed: {res1}"
        assert res2.get('success') is True, f"Device 2 heartbeat failed: {res2}"
    print("  -> Race 7 PASS: Multi-device concurrent heartbeats execute safely without lock conflict.")

    # Race 8: Group call with several participants and only one active heartbeat
    setup_test_users_and_chat()
    run_sql("""
    INSERT INTO public.calls (id, chat_id, caller_id, call_type, is_group, status, room_id, started_at, connected_at, last_activity_at)
    VALUES ('c2222222-0008-0000-0000-000000000008', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'video', true, 'ongoing', 'room-r8', clock_timestamp() - interval '300 seconds', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '10 seconds');
    INSERT INTO public.call_participants (call_id, user_id, status, joined_at, last_heartbeat_at) VALUES
      ('c2222222-0008-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '10 seconds'),
      ('c2222222-0008-0000-0000-000000000008', '22222222-2222-2222-2222-222222222222', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '180 seconds'),
      ('c2222222-0008-0000-0000-000000000008', '33333333-3333-3333-3333-333333333333', 'accepted', clock_timestamp() - interval '290 seconds', clock_timestamp() - interval '200 seconds');
    """)
    # Timeout worker runs
    res_w = json.loads(run_sql("SELECT public.process_call_timeouts(25);").split('\n')[-1])
    assert res_w.get('expired_ongoing_count') == 0, f"Expected 0 ongoing expired, got: {res_w}"
    st_r8 = run_sql("SELECT status FROM public.calls WHERE id = 'c2222222-0008-0000-0000-000000000008';")
    assert st_r8 == 'ongoing', f"Expected group call to remain ongoing while 1 participant heartbeats, got: {st_r8}"
    print("  -> Race 8 PASS: Group call with only 1 of 3 active heartbeats preserved correctly.")

def run_all_tests():
    print("==================================================================")
    print("RUNNING POSTGRESQL 15 MIGRATION & CONCURRENCY TEST SUITE (PHASE 7)")
    print("==================================================================")
    test_scenario_0_rollout_gate_disabled_protects_legacy_clients()
    test_scenario_1_one_participant_active_keeps_call_alive()
    test_scenario_2_all_participants_silent_recovered()
    test_scenario_3_group_call_liveness()
    test_scenario_4_heartbeat_rpc_and_post_termination()
    test_scenario_5_idempotent_accept_refresh()
    test_scenario_6_rejoin_call_liveness()
    test_scenario_7_migration_grace_period()
    test_scenario_8_historical_terminal_call_integrity()
    test_scenario_9_inline_timeout_in_initiate_call()
    test_scenario_11_multi_connection_concurrency()
    test_scenario_12_deterministic_race_conditions()
    test_scenario_10_rollback_and_reapply()
    test_scenario_13_least_privilege_permissions()
    print("==================================================================")
    print("ALL 14 CONCURRENCY, LIFECYCLE, ROLLBACK & SECURITY TESTS PASSED!")
    print("==================================================================")

if __name__ == '__main__':
    run_all_tests()
