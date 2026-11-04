-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Step 2: Safe Utilities, Security Definer Helpers, Table Grants, and RLS Policies
-- File: supabase/migrations/20261026000002_security_helpers_and_rls.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SAFE UUID UTILITY
-- ------------------------------------------------------------------------------
-- Safe UUID parser: Returns NULL instead of throwing fatal syntax errors on non-UUID paths
create or replace function public.safe_uuid(p_val text)
returns uuid
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p_val is not null and p_val ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return p_val::uuid;
  end if;
  return null;
exception
  when others then
    return null;
end;
$$;

revoke all on function public.safe_uuid(text) from public, anon;
grant execute on function public.safe_uuid(text) to authenticated;

-- ------------------------------------------------------------------------------
-- 2. SCOPED RECURSION-BREAKING SECURITY DEFINER HELPERS
-- ------------------------------------------------------------------------------

-- Caller membership check: Binds strictly to auth.uid(), preventing third-party probing
create or replace function public.is_chat_member(p_chat_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members
    where chat_id = p_chat_id and user_id = auth.uid()
  );
$$;

-- Caller admin check: Binds strictly to auth.uid()
create or replace function public.is_chat_admin(p_chat_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members
    where chat_id = p_chat_id and user_id = auth.uid() and role = 'admin'
  );
$$;

-- Caller mutual chat check: Binds strictly to auth.uid()
create or replace function public.share_a_chat(p_target_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members cm1
    join public.chat_members cm2 on cm1.chat_id = cm2.chat_id
    where cm1.user_id = auth.uid() and cm2.user_id = p_target_user_id
  );
$$;

-- Safe chat creator lookup: returns creator ONLY if caller is a member or creator
create or replace function public.get_chat_creator(p_chat_id uuid)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select created_by from public.chats
  where id = p_chat_id
    and (created_by = auth.uid() or exists (select 1 from public.chat_members where chat_id = p_chat_id and user_id = auth.uid()));
$$;

revoke all on function public.is_chat_member(uuid) from public, anon;
grant execute on function public.is_chat_member(uuid) to authenticated;

revoke all on function public.is_chat_admin(uuid) from public, anon;
grant execute on function public.is_chat_admin(uuid) to authenticated;

revoke all on function public.share_a_chat(uuid) from public, anon;
grant execute on function public.share_a_chat(uuid) to authenticated;

revoke all on function public.get_chat_creator(uuid) from public, anon;
grant execute on function public.get_chat_creator(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 3. COLUMN-LEVEL LEAST PRIVILEGE GRANTS
-- ------------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- PROFILES: Select and Insert allowed; Update restricted to mutable profile columns
grant select, insert on public.profiles to authenticated;
grant update (display_name, avatar_url, about, links, last_seen, updated_at) on public.profiles to authenticated;

-- CHATS: Select allowed; Insert restricted to create payload; Update restricted to title/avatar/updated_at
grant select on public.chats to authenticated;
grant insert (id, type, title, avatar_url, created_by) on public.chats to authenticated;
grant update (title, avatar_url, updated_at) on public.chats to authenticated;

-- CHAT MEMBERS: Select and Insert allowed; Update restricted to user preferences (unread_count, muted)
-- NOTE: DELETE is intentionally revoked from authenticated. All departures must pass through remove_chat_member() or leave_chat().
grant select on public.chat_members to authenticated;
grant insert (chat_id, user_id, role) on public.chat_members to authenticated;
grant update (unread_count, muted) on public.chat_members to authenticated;

-- MESSAGES: Select and Insert allowed
-- NOTE: UPDATE is intentionally revoked from authenticated. Monotonic forward status promotions must pass through promote_message_status() or mark_chat_read().
grant select on public.messages to authenticated;
grant insert (id, chat_id, sender_id, type, text, media, status, sent_at) on public.messages to authenticated;

-- USER DEVICES: Full self CRUD for authenticated push token registration
grant select, insert, update, delete on public.user_devices to authenticated;

-- Strip inherited default table privileges on internal rate-limiting infrastructure
revoke all on public.contact_match_rate_limits from anon, authenticated, public;

revoke all on public.push_rate_limits from anon, authenticated, public;
grant all on public.push_rate_limits to service_role;

-- ------------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------

-- PROFILES
drop policy if exists "profiles_select_mutual_or_self" on public.profiles;
create policy "profiles_select_mutual_or_self" on public.profiles
  for select to authenticated
  using (auth.uid() = id or public.share_a_chat(id));

drop policy if exists "profiles_select_definer" on public.profiles;
create policy "profiles_select_definer" on public.profiles
  for select to app_contacts_definer using (true);

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
  for insert to authenticated
  with check (auth.uid() = id and phone_e164 is not distinct from nullif(auth.jwt() ->> 'phone', ''));

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- CHATS
drop policy if exists "chats_select_member" on public.chats;
create policy "chats_select_member" on public.chats
  for select to authenticated using (public.is_chat_member(id));

-- Direct table insertion only permitted for groups. Direct chats are created via get_or_create_direct_chat()
drop policy if exists "chats_insert_group_creator" on public.chats;
create policy "chats_insert_group_creator" on public.chats
  for insert to authenticated
  with check (auth.uid() = created_by and type = 'group');

drop policy if exists "chats_update_admin_or_creator" on public.chats;
create policy "chats_update_admin_or_creator" on public.chats
  for update to authenticated
  using (auth.uid() = created_by or public.is_chat_admin(id))
  with check (auth.uid() = created_by or public.is_chat_admin(id));

-- CHAT MEMBERS
drop policy if exists "chat_members_select_member" on public.chat_members;
create policy "chat_members_select_member" on public.chat_members
  for select to authenticated using (public.is_chat_member(chat_id));

-- Member insertion: only chat creator (during group creation) or existing chat admin can add members to a group
drop policy if exists "chat_members_insert_authorized" on public.chat_members;
create policy "chat_members_insert_authorized" on public.chat_members
  for insert to authenticated
  with check (
    (auth.uid() = public.get_chat_creator(chat_id) or public.is_chat_admin(chat_id))
    and exists (select 1 from public.chats c where c.id = chat_id and c.type = 'group')
  );

-- Preference updates: users can update unread count and muted for self, never role
drop policy if exists "chat_members_update_self_preferences" on public.chat_members;
create policy "chat_members_update_self_preferences" on public.chat_members
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and role in ('admin', 'member'));

-- MESSAGES
drop policy if exists "messages_select_member" on public.messages;
create policy "messages_select_member" on public.messages
  for select to authenticated using (public.is_chat_member(chat_id));

drop policy if exists "messages_insert_sender" on public.messages;
create policy "messages_insert_sender" on public.messages
  for insert to authenticated
  with check (
    auth.uid() = sender_id
    and public.is_chat_member(chat_id)
    and status in (0, 1)
    and type in ('text', 'media', 'call')
  );

-- USER DEVICES
drop policy if exists "user_devices_all_self" on public.user_devices;
create policy "user_devices_all_self" on public.user_devices
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- RATE LIMITS
drop policy if exists "rate_limits_definer_all" on public.contact_match_rate_limits;
create policy "rate_limits_definer_all" on public.contact_match_rate_limits
  for all to app_contacts_definer using (true) with check (true);

drop policy if exists "push_rate_limits_service_all" on public.push_rate_limits;
create policy "push_rate_limits_service_all" on public.push_rate_limits
  for all to service_role using (true) with check (true);
