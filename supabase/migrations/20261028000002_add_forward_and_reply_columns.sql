-- Migration: Add forward and reply columns to messages table
-- Reference reconstruction for Issue 4: Forward Message and Reply Message features

-- 1. ADD COLUMNS
alter table public.messages
  add column if not exists is_forwarded boolean not null default false,
  add column if not exists reply_to_message_id uuid references public.messages(id) on delete set null,
  add column if not exists reply_snapshot jsonb;

-- 2. CREATE INDEX FOR REPLIES LOOKUP
create index if not exists idx_messages_reply_to_message_id
  on public.messages (reply_to_message_id)
  where reply_to_message_id is not null;

-- 3. GRANT COLUMN INSERT PRIVILEGES TO AUTHENTICATED
grant insert (is_forwarded, reply_to_message_id, reply_snapshot)
  on public.messages to authenticated;

-- 4. VALIDATION TRIGGER FOR REPLIES (Same Chat Integrity)
create or replace function public.validate_message_reply()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.reply_to_message_id is not null then
    if not exists (
      select 1 from public.messages
      where id = new.reply_to_message_id and chat_id = new.chat_id
    ) then
      raise exception 'reply_to_message_id must belong to the same chat'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_message_reply on public.messages;
create trigger trg_validate_message_reply
  before insert or update of reply_to_message_id on public.messages
  for each row
  execute function public.validate_message_reply();
