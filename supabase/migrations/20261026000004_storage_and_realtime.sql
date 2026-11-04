-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Step 4: Storage Buckets, Storage RLS Policies, Realtime Replica Identity & Topic Authorization
-- File: supabase/migrations/20261026000004_storage_and_realtime.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. STORAGE BUCKETS CONFIGURATION
-- ------------------------------------------------------------------------------
-- Ensure avatars (public profile/group images) and attachments (private media) exist
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('attachments', 'attachments', false, 104857600, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'application/pdf', 'text/plain'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ------------------------------------------------------------------------------
-- 2. STORAGE ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------

-- AVATARS POLICIES:
-- Authenticated and anonymous users can read avatars in the public avatars bucket
drop policy if exists "avatars_select_authenticated" on storage.objects;
create policy "avatars_select_authenticated" on storage.objects
  for select to authenticated using (bucket_id = 'avatars');

drop policy if exists "avatars_select_anon" on storage.objects;
create policy "avatars_select_anon" on storage.objects
  for select to anon using (bucket_id = 'avatars');

-- Users can only upload avatars under their own folder: "{owner_id}/..."
drop policy if exists "avatars_insert_owner" on storage.objects;
create policy "avatars_insert_owner" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and owner = auth.uid()
  );

drop policy if exists "avatars_update_owner" on storage.objects;
create policy "avatars_update_owner" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and owner = auth.uid()
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and owner = auth.uid()
  );

drop policy if exists "avatars_delete_owner" on storage.objects;
create policy "avatars_delete_owner" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ATTACHMENTS POLICIES:
-- Attachments are partitioned by chat_id: "{chat_id}/{message_id}_{filename}"
-- Uses public.safe_uuid to safely parse folder name without crashing on non-UUID paths
drop policy if exists "attachments_select_member" on storage.objects;
create policy "attachments_select_member" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and public.is_chat_member(public.safe_uuid((storage.foldername(name))[1]))
  );

-- Only active chat members can upload attachments to the chat folder
drop policy if exists "attachments_insert_member" on storage.objects;
create policy "attachments_insert_member" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and owner = auth.uid()
    and public.is_chat_member(public.safe_uuid((storage.foldername(name))[1]))
  );

-- Only active chat members who own the object can update/upsert attachments
drop policy if exists "attachments_update_member" on storage.objects;
create policy "attachments_update_member" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'attachments'
    and owner = auth.uid()
    and public.is_chat_member(public.safe_uuid((storage.foldername(name))[1]))
  )
  with check (
    bucket_id = 'attachments'
    and owner = auth.uid()
    and public.is_chat_member(public.safe_uuid((storage.foldername(name))[1]))
  );

-- Media attachments can be deleted by the uploader OR a chat administrator
drop policy if exists "attachments_delete_authorized" on storage.objects;
create policy "attachments_delete_authorized" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attachments'
    and (
      owner = auth.uid()
      or public.is_chat_admin(public.safe_uuid((storage.foldername(name))[1]))
    )
  );

-- ------------------------------------------------------------------------------
-- 3. REALTIME REPLICA IDENTITY & PUBLICATION REGISTRATION
-- ------------------------------------------------------------------------------
alter table public.messages replica identity full;
alter table public.chats replica identity full;
alter table public.chat_members replica identity full;
alter table public.profiles replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chats'
  ) then
    alter publication supabase_realtime add table public.chats;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_members'
  ) then
    alter publication supabase_realtime add table public.chat_members;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end
$$;

-- ------------------------------------------------------------------------------
-- 4. REALTIME PRIVATE CHANNEL TOPIC AUTHORIZATION POLICIES (realtime.messages)
-- ------------------------------------------------------------------------------
-- Authorizes broadcast listening and publishing on 'chat_typing:<chat_id>' topics
-- strictly for active chat participants via Postgres RLS on realtime.messages.
drop policy if exists "chat_typing_select_member" on realtime.messages;
create policy "chat_typing_select_member"
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and realtime.topic() like 'chat_typing:%'
  and public.is_chat_member(public.safe_uuid(split_part(realtime.topic(), ':', 2)))
);

drop policy if exists "chat_typing_insert_member" on realtime.messages;
create policy "chat_typing_insert_member"
on realtime.messages
for insert
to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and realtime.topic() like 'chat_typing:%'
  and public.is_chat_member(public.safe_uuid(split_part(realtime.topic(), ':', 2)))
);
