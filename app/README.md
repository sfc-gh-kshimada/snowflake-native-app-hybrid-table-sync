# Hybrid Lookup (Native App PoC)

Provider-shared table -> app-owned **hybrid table** (incremental MERGE by `_SNOWFLAKE_UPDATED_AT`),
with an in-app Cortex Agent and a Streamlit UI (direct lookup / Cortex Agents).

After install:
```sql
GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION <app>;
CREATE WAREHOUSE IF NOT EXISTS HT_APP_WH WAREHOUSE_SIZE = XSMALL;
GRANT USAGE        ON WAREHOUSE HT_APP_WH TO APPLICATION <app>;
GRANT CALLER USAGE ON WAREHOUSE HT_APP_WH TO APPLICATION <app>;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION <app>;   -- Streamlit -> agent
CALL <app>.api.init();          -- initial load + sync task
GRANT APPLICATION ROLE <app>.app_user TO ROLE <user_role>;
```
Then open the Streamlit `API.DEMO_UI`, or use `AGENT.RESERVATION_AGENT` from Snowflake CoWork.
