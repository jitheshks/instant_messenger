-- Rollback: 20261104000002_harden_app_settings_least_privilege_rollback.sql
-- Restores direct SELECT grant and permissive read policy for authenticated, anon.

GRANT SELECT ON TABLE public.app_settings TO authenticated, anon;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'app_settings' AND policyname = 'app_settings_read'
  ) THEN
    CREATE POLICY "app_settings_read"
      ON public.app_settings
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;
