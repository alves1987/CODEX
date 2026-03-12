# Monitoramento em tempo real de tabelas no e-SUS (PostgreSQL)

Sim — existe uma forma robusta de saber **quais tabelas foram alteradas** quando qualquer ação acontece no sistema.

Como você usa PostgreSQL (`jdbc:postgresql://localhost:5432/esus`, usuário/senha `esus`), a abordagem mais prática é:

1. **Auditar no banco** com trigger genérica (INSERT/UPDATE/DELETE).
2. **Emitir evento em tempo real** com `NOTIFY`.
3. **Consumir eventos em uma tela** (dashboard web com WebSocket/SSE).

---

## 1) Estrutura de auditoria no banco

Crie um schema e uma tabela de auditoria:

```sql
CREATE SCHEMA IF NOT EXISTS monitor;

CREATE TABLE IF NOT EXISTS monitor.audit_log (
  id               BIGSERIAL PRIMARY KEY,
  event_ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  txid             BIGINT NOT NULL DEFAULT txid_current(),
  schema_name      TEXT NOT NULL,
  table_name       TEXT NOT NULL,
  operation        TEXT NOT NULL, -- INSERT / UPDATE / DELETE
  user_name        TEXT,
  application_name TEXT,
  client_addr      INET,
  row_old          JSONB,
  row_new          JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_log_event_ts ON monitor.audit_log (event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_table    ON monitor.audit_log (schema_name, table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_op       ON monitor.audit_log (operation);
```

---

## 2) Função genérica de trigger

Essa função grava no log e envia notificação para canal `table_changes`.

```sql
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
      'op', TG_OP
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
      'op', TG_OP
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
      'op', TG_OP
    );

    PERFORM pg_notify('table_changes', v_payload::text);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;
```

---

## 3) Aplicar trigger em lote nas tabelas de interesse

Você pode começar por prefixos (`tb_`, `ta_`, `tl_`, `rl_`).

```sql
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
```

> Dica: se o volume for muito alto, audite primeiro apenas tabelas críticas.

---

## 4) Consulta rápida para ver “o que mudou agora”

```sql
SELECT
  event_ts,
  schema_name,
  table_name,
  operation,
  user_name
FROM monitor.audit_log
ORDER BY event_ts DESC
LIMIT 200;
```

Resumo por tabela:

```sql
SELECT
  table_name,
  count(*) AS total_eventos,
  max(event_ts) AS ultima_alteracao
FROM monitor.audit_log
GROUP BY table_name
ORDER BY ultima_alteracao DESC;
```

---

## 5) Em tempo real: backend + tela

Fluxo sugerido:

- Backend abre conexão PostgreSQL e executa `LISTEN table_changes;`
- Ao receber `NOTIFY`, publica via WebSocket/SSE para frontend.
- Frontend exibe grade em tempo real (timestamp, tabela, operação, usuário).

### Exemplo mínimo de listener (Node.js)

```js
import pg from 'pg';

const client = new pg.Client({
  host: 'localhost',
  port: 5432,
  database: 'esus',
  user: 'esus',
  password: 'esus'
});

await client.connect();
await client.query('LISTEN table_changes');

client.on('notification', (msg) => {
  const payload = JSON.parse(msg.payload);
  console.log('Mudança:', payload);
  // daqui você envia para websocket/sse
});
```

---

## 6) Cuidados importantes

- **Performance**: trigger em muitas tabelas aumenta custo de escrita.
- **LGPD/sigilo**: talvez seja melhor não armazenar `row_new/row_old` completos em tabelas sensíveis.
- **Retenção**: crie política de limpeza (ex.: manter 30/90 dias).
- **Particionamento**: em ambientes grandes, particione `monitor.audit_log` por mês.

---

## 7) Alternativas

- **pgAudit**: excelente para auditoria em nível SQL, mas geralmente exige ajuste no servidor.
- **Logical decoding / CDC** (Debezium/Kafka): ótimo para observabilidade avançada, porém mais complexo.
- **Logs do app**: útil para ação de negócio, mas não substitui auditoria transacional no banco.

---

## Recomendação prática para começar hoje

1. Criar `monitor.audit_log` e `monitor.fn_audit_dml`.
2. Ativar trigger só em um subconjunto crítico de tabelas.
3. Validar impacto.
4. Ligar `LISTEN/NOTIFY` em um backend simples.
5. Criar painel em tempo real com filtros por tabela/operação/período.

Com isso, você passa a enxergar exatamente **quais tabelas mudam a cada ação do sistema**, quase em tempo real.
