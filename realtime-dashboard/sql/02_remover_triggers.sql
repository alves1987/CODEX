DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT event_object_schema AS table_schema, event_object_table AS table_name
      FROM information_schema.triggers
     WHERE trigger_name = 'tr_audit_dml'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS tr_audit_dml ON %I.%I;', r.table_schema, r.table_name);
  END LOOP;
END $$;
