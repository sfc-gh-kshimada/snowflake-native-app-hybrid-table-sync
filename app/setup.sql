CREATE APPLICATION ROLE IF NOT EXISTS app_user;

-- state schema (not versioned): hybrid table + sync state
CREATE SCHEMA IF NOT EXISTS core;
CREATE HYBRID TABLE IF NOT EXISTS core.reservation_ht (
  reservation_id NUMBER PRIMARY KEY,
  tenant_id      VARCHAR NOT NULL,
  phone_number   VARCHAR,
  customer_name  VARCHAR,
  status         VARCHAR,
  reserved_at    TIMESTAMP_NTZ,
  src_updated_at TIMESTAMP_NTZ,
  INDEX idx_phone (phone_number)
);
CREATE TABLE IF NOT EXISTS core.sync_state (tbl VARCHAR, last_ts TIMESTAMP_NTZ, synced_at TIMESTAMP_LTZ);

-- code schema (versioned)
CREATE OR ALTER VERSIONED SCHEMA api;
GRANT USAGE ON SCHEMA api TO APPLICATION ROLE app_user;

-- incremental sync: watermark on _SNOWFLAKE_UPDATED_AT, 5 min overlap (MERGE is idempotent)
CREATE OR REPLACE PROCEDURE api.sync_reservation()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  wm TIMESTAMP_NTZ;
  new_wm TIMESTAMP_NTZ;
  n NUMBER;
BEGIN
  SELECT COALESCE(MAX(last_ts), '1970-01-01'::TIMESTAMP_NTZ) INTO :wm
    FROM core.sync_state WHERE tbl = 'reservation';

  -- fix upper bound first so rows arriving during MERGE are picked up next run
  SELECT COUNT(*), MAX(_SNOWFLAKE_UPDATED_AT) INTO :n, :new_wm
    FROM shared_schema.reservation
    WHERE _SNOWFLAKE_UPDATED_AT > DATEADD(minute, -5, :wm);
  IF (n = 0) THEN
    RETURN 'no change (wm=' || wm::VARCHAR || ')';
  END IF;

  MERGE INTO core.reservation_ht t
  USING (SELECT * FROM shared_schema.reservation
         WHERE _SNOWFLAKE_UPDATED_AT > DATEADD(minute, -5, :wm)
           AND _SNOWFLAKE_UPDATED_AT <= :new_wm) s
    ON t.reservation_id = s.reservation_id
  WHEN MATCHED AND s._SNOWFLAKE_DELETED THEN DELETE
  WHEN MATCHED AND NOT s._SNOWFLAKE_DELETED THEN UPDATE SET
    tenant_id = s.tenant_id, phone_number = s.phone_number, customer_name = s.customer_name,
    status = s.status, reserved_at = s.reserved_at, src_updated_at = s._SNOWFLAKE_UPDATED_AT
  WHEN NOT MATCHED AND NOT s._SNOWFLAKE_DELETED THEN INSERT
    (reservation_id, tenant_id, phone_number, customer_name, status, reserved_at, src_updated_at)
    VALUES (s.reservation_id, s.tenant_id, s.phone_number, s.customer_name, s.status, s.reserved_at, s._SNOWFLAKE_UPDATED_AT);

  DELETE FROM core.sync_state WHERE tbl = 'reservation';
  INSERT INTO core.sync_state VALUES ('reservation', :new_wm, CURRENT_TIMESTAMP());
  RETURN 'merged ' || n::VARCHAR || ' rows (wm=' || new_wm::VARCHAR || ')';
END;
$$;
GRANT USAGE ON PROCEDURE api.sync_reservation() TO APPLICATION ROLE app_user;

-- lookup API (tool for Cortex Agents)
CREATE OR REPLACE PROCEDURE api.lookup_by_phone(phone VARCHAR)
RETURNS TABLE (reservation_id NUMBER, customer_name VARCHAR, status VARCHAR, reserved_at TIMESTAMP_NTZ, src_updated_at TIMESTAMP_NTZ)
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  rs RESULTSET DEFAULT (
    SELECT reservation_id, customer_name, status, reserved_at, src_updated_at
    FROM core.reservation_ht
    WHERE phone_number = :phone
    ORDER BY reserved_at DESC
    LIMIT 50);
BEGIN
  RETURN TABLE(rs);
END;
$$;
GRANT USAGE ON PROCEDURE api.lookup_by_phone(VARCHAR) TO APPLICATION ROLE app_user;

-- agent tool: Cortex Agents custom tools need a single-cell result -> return VARIANT (JSON array)
CREATE OR REPLACE PROCEDURE api.lookup_by_phone_json(phone VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE res VARIANT;
BEGIN
  SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT(
           'reservation_id', reservation_id, 'customer_name', customer_name, 'status', status,
           'reserved_at', reserved_at, 'src_updated_at', src_updated_at))
           WITHIN GROUP (ORDER BY reserved_at DESC), ARRAY_CONSTRUCT())
    INTO :res
    FROM (SELECT * FROM core.reservation_ht WHERE phone_number = :phone ORDER BY reserved_at DESC LIMIT 50);
  RETURN res;
END;
$$;
GRANT USAGE ON PROCEDURE api.lookup_by_phone_json(VARCHAR) TO APPLICATION ROLE app_user;

-- read-only view for consumers
CREATE OR REPLACE VIEW api.reservation_v AS SELECT * FROM core.reservation_ht;
GRANT SELECT ON VIEW api.reservation_v TO APPLICATION ROLE app_user;

CREATE OR REPLACE VIEW api.sync_status_v AS SELECT tbl, last_ts, synced_at FROM core.sync_state;
GRANT SELECT ON VIEW api.sync_status_v TO APPLICATION ROLE app_user;

-- agent lives in a non-versioned schema (created at init because tool needs consumer warehouse)
CREATE SCHEMA IF NOT EXISTS agent;
GRANT USAGE ON SCHEMA agent TO APPLICATION ROLE app_user;

-- init: initial load + task + agent. consumer must: GRANT USAGE ON WAREHOUSE <wh> TO APPLICATION <app>
CREATE OR REPLACE PROCEDURE api.init(wh VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE r VARCHAR; app VARCHAR; spec VARCHAR;
BEGIN
  CALL api.sync_reservation() INTO :r;
  CREATE TASK IF NOT EXISTS core.sync_task
    SCHEDULE = '1 MINUTE'
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  AS CALL api.sync_reservation();
  ALTER TASK core.sync_task RESUME;

  app := CURRENT_DATABASE();
  spec := '
models:
  orchestration: auto
instructions:
  response: "日本語で簡潔に回答してください。予約一覧は表形式で示してください。"
  orchestration: "電話番号で予約を調べる質問には lookup_by_phone ツールを使ってください。電話番号はハイフン付き(例: 090-0000-0001)で渡してください。"
tools:
  - tool_spec:
      type: generic
      name: lookup_by_phone
      description: "電話番号から予約(予約ID、顧客名、ステータス、予約日時)を最大50件返す。データはハイブリッドテーブルから取得。"
      input_schema:
        type: object
        properties:
          phone: {type: string, description: "電話番号 (例: 090-0000-0001)"}
        required: [phone]
tool_resources:
  lookup_by_phone:
    type: procedure
    identifier: ' || app || '.API.LOOKUP_BY_PHONE_JSON
    execution_environment: {type: warehouse, warehouse: ' || wh || '}
';
  EXECUTE IMMEDIATE 'CREATE OR REPLACE AGENT agent.reservation_agent FROM SPECIFICATION ' || CHR(36) || CHR(36) || spec || CHR(36) || CHR(36);
  EXECUTE IMMEDIATE 'GRANT USAGE ON AGENT agent.reservation_agent TO APPLICATION ROLE app_user';
  RETURN 'initial: ' || r || ' / task resumed / agent created';
END;
$$;
GRANT USAGE ON PROCEDURE api.init(VARCHAR) TO APPLICATION ROLE app_user;

-- Streamlit UI
CREATE OR REPLACE STREAMLIT api.demo_ui
  FROM '/streamlit'
  MAIN_FILE = '/app.py';
GRANT USAGE ON STREAMLIT api.demo_ui TO APPLICATION ROLE app_user;
