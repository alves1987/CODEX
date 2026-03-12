CREATE SCHEMA IF NOT EXISTS monitor;

CREATE TABLE IF NOT EXISTS monitor.audit_log (
  id               BIGSERIAL PRIMARY KEY,
  event_ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  txid             BIGINT NOT NULL DEFAULT txid_current(),
  schema_name      TEXT NOT NULL,
  table_name       TEXT NOT NULL,
  operation        TEXT NOT NULL,
  user_name        TEXT,
  application_name TEXT,
  client_addr      INET,
  row_old          JSONB,
  row_new          JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_log_event_ts ON monitor.audit_log (event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_table ON monitor.audit_log (schema_name, table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_op ON monitor.audit_log (operation);

CREATE OR REPLACE FUNCTION monitor.fn_audit_dml()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_payload JSON;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO monitor.audit_log (
      schema_name, table_name, operation,
      user_name, application_name, client_addr,
      row_old, row_new
    ) VALUES (
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP,
      session_user, current_setting('application_name', true), inet_client_addr(),
      NULL, to_jsonb(NEW)
    );

    v_payload := json_build_object(
      'ts', now(),
      'schema', TG_TABLE_SCHEMA,
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'user', session_user
    );

    PERFORM pg_notify('table_changes', v_payload::text);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO monitor.audit_log (
      schema_name, table_name, operation,
      user_name, application_name, client_addr,
      row_old, row_new
    ) VALUES (
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP,
      session_user, current_setting('application_name', true), inet_client_addr(),
      to_jsonb(OLD), to_jsonb(NEW)
    );

    v_payload := json_build_object(
      'ts', now(),
      'schema', TG_TABLE_SCHEMA,
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'user', session_user
    );

    PERFORM pg_notify('table_changes', v_payload::text);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO monitor.audit_log (
      schema_name, table_name, operation,
      user_name, application_name, client_addr,
      row_old, row_new
    ) VALUES (
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP,
      session_user, current_setting('application_name', true), inet_client_addr(),
      to_jsonb(OLD), NULL
    );

    v_payload := json_build_object(
      'ts', now(),
      'schema', TG_TABLE_SCHEMA,
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'user', session_user
    );

    PERFORM pg_notify('table_changes', v_payload::text);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_schema = 'public'
      AND (
        table_name LIKE 'tb\_%' ESCAPE '\\'
        OR table_name LIKE 'ta\_%' ESCAPE '\\'
        OR table_name LIKE 'tl\_%' ESCAPE '\\'
        OR table_name LIKE 'rl\_%' ESCAPE '\\'
      )
      AND table_name <> 'audit_log'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS tr_audit_dml ON %I.%I;', r.table_schema, r.table_name);

    EXECUTE format(
      'CREATE TRIGGER tr_audit_dml
       AFTER INSERT OR UPDATE OR DELETE ON %I.%I
       FOR EACH ROW EXECUTE FUNCTION monitor.fn_audit_dml();',
      r.table_schema, r.table_name
    );
  END LOOP;
END $$;
