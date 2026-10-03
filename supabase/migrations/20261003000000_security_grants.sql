-- Apply after the historical production migrations recovered from the backup.
-- Remove PostgreSQL's implicit PUBLIC execute grant as well as direct grants.
-- Sensitive mutations must go through authenticated Edge Functions.
DO $block$
DECLARE fn regprocedure;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'create_inventory_item_tx', 'dispatch_item_tx', 'return_item_tx',
      'update_item_basic_fields_tx', 'archive_item_tx',
      'claim_pending_approval_tx', 'revoke_all_sessions'
    )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END
$block$;

ALTER VIEW public.inventory_items_grouped SET (security_invoker = true);

-- Password hashes are only needed by the service-role login function.
REVOKE SELECT ON public.users FROM anon, authenticated;
GRANT SELECT (username, role, can_export, can_track, can_edit, status)
  ON public.users TO anon, authenticated;

