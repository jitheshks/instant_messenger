-- ==============================================================================
-- Instant Messenger — Supabase Database Migration
-- Step 1: Core Schema, Extensions, Roles, Tables, and Constraints
-- File: supabase/migrations/20261026000001_core_schema.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. EXTENSIONS & SAFE SCHEMAS
-- ------------------------------------------------------------------------------
create schema if not exists extensions;
grant usage on schema extensions to authenticated, service_role;

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "pgcrypto" with schema extensions;

-- ------------------------------------------------------------------------------
-- 2. DEDICATED LEAST-PRIVILEGED ROLE (CONTACT MATCHING)
-- ------------------------------------------------------------------------------
do $$
begin
  if not exists (select from pg_roles where rolname = 'app_contacts_definer') then
    create role app_contacts_definer with nologin nosuperuser;
  end if;
end
$$;

-- Ensure postgres inherits definer ownership for rerun idempotency and maintenance
grant app_contacts_definer to postgres with inherit true, set true;

grant usage on schema public to app_contacts_definer;
grant usage on schema auth to app_contacts_definer;
grant execute on function auth.uid() to app_contacts_definer;

-- ------------------------------------------------------------------------------
-- 3. CORE APPLICATION TABLES & CONSTRAINTS
-- ------------------------------------------------------------------------------

-- PROFILES
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text unique,
  display_name text not null default '',
  avatar_url text,
  about text not null default 'Hey there! I am using Instant Messenger.',
  links text[] not null default '{}',
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- CHATS
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'direct' check (type in ('direct', 'group')),
  title text not null default '',
  avatar_url text,
  created_by uuid references auth.users(id) on delete set null,
  last_message text not null default '',
  last_message_time timestamptz not null default now(),
  last_sender_id uuid references auth.users(id) on delete set null,
  last_message_status int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_chats_updated_at
  on public.chats (updated_at desc);

alter table public.chats enable row level security;

-- CHAT MEMBERS
create table if not exists public.chat_members (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  unread_count int not null default 0,
  muted boolean not null default false,
  last_read_at timestamptz not null default now(),
  joined_at timestamptz not null default now(),
  primary key (chat_id, user_id),
  constraint fk_chat_members_profiles foreign key (user_id) references public.profiles(id) on delete cascade
);

create index if not exists idx_chat_members_user_id
  on public.chat_members (user_id);

alter table public.chat_members enable row level security;

-- MESSAGES
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  type text not null default 'text' check (type in ('text', 'media', 'call')),
  text text not null default '',
  media jsonb,
  status int not null default 1, -- 0=sending, 1=sent, 2=delivered, 3=read
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_messages_status') then
    alter table public.messages add constraint chk_messages_status check (status in (0, 1, 2, 3));
  end if;
end
$$;

create index if not exists idx_messages_chat_sent
  on public.messages (chat_id, sent_at desc);

create index if not exists idx_messages_sent_at_id
  on public.messages (sent_at asc, id asc);

alter table public.messages enable row level security;

-- USER DEVICES (PUSH NOTIFICATION TOKENS)
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  player_id text not null check (length(trim(player_id)) > 0),
  platform text not null default 'android' check (platform in ('android', 'ios', 'web')),
  app_version text check (app_version is null or length(app_version) <= 64),
  subscribed boolean not null default true,
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint uq_user_devices_player_id unique (player_id)
);

create index if not exists idx_user_devices_user_subscribed
  on public.user_devices (user_id) where (subscribed = true);

alter table public.user_devices enable row level security;

-- CONTACT MATCH RATE LIMITS
create table if not exists public.contact_match_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  request_count int not null default 1,
  window_start timestamptz not null default now()
);

alter table public.contact_match_rate_limits enable row level security;

-- PUSH RATE LIMITS (EDGE FUNCTION ISOLATE SYNCHRONIZATION)
create table if not exists public.push_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  request_count int not null default 1,
  window_start timestamptz not null default now()
);

alter table public.push_rate_limits enable row level security;
