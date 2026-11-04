-- ------------------------------------------------------------------------------
-- ALIGN MATCH_CONTACTS OWNER TO POSTGRES (SUPABASE HOSTED EXECUTION COMPATIBILITY)
-- In hosted Supabase, the auth schema is owned by supabase_admin. Custom definer
-- roles cannot be granted USAGE on auth by postgres. Transferring ownership to
-- postgres aligns match_contacts with all other project RPCs (get_or_create_direct_chat,
-- register_device, send_message) and enables auth.uid() resolution while preserving
-- atomic rate limiting and phone normalization.
-- ------------------------------------------------------------------------------
alter function public.match_contacts(text[]) owner to postgres;
revoke all on function public.match_contacts(text[]) from public, anon;
grant execute on function public.match_contacts(text[]) to authenticated;
