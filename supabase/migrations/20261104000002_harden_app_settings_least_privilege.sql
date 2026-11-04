-- Migration: 20261104000002_harden_app_settings_least_privilege.sql
-- Description: Enforce strict least-privilege on public.app_settings.
-- Revokes direct table-level SELECT from public, anon, and authenticated.
-- Drops client-facing SELECT RLS policy. Direct table reads are prohibited for client roles.
-- Controlled reads are exclusively permitted through public.is_feature_enabled(text) [SECURITY DEFINER].
-- Retains administrative access for service_role and table owner postgres.

-- 1. Revoke direct table permissions from client roles
REVOKE ALL ON TABLE public.app_settings FROM PUBLIC, anon, authenticated;

-- 2. Drop client-facing RLS policy if present
DROP POLICY IF EXISTS "app_settings_read" ON public.app_settings;

-- 3. Ensure Row Level Security remains strictly enabled
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- 4. Grant full administrative privileges to service_role
GRANT ALL ON TABLE public.app_settings TO service_role;

-- 5. Validate that is_feature_enabled is SECURITY DEFINER with empty search_path
-- and grant execute to client roles and service_role for controlled evaluations.
CREATE OR REPLACE FUNCTION public.is_feature_enabled(p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT value = 'true' FROM public.app_settings WHERE key = p_key),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_feature_enabled(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_feature_enabled(text) TO authenticated, anon, service_role;

-- 6. Ensure the rollout gate default remains strictly disabled
INSERT INTO public.app_settings (key, value, description)
VALUES ('calling_heartbeat_recovery_enabled', 'false', 'Enables ongoing abandoned call recovery via heartbeats')
ON CONFLICT (key) DO UPDATE
SET value = 'false'
WHERE public.app_settings.key = 'calling_heartbeat_recovery_enabled'
  AND public.app_settings.value IS NULL;
