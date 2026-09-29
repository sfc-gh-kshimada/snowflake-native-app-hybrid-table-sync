# Hybrid Lookup (Native App PoC)

Provider-shared table -> app-owned **hybrid table** (incremental MERGE by `_SNOWFLAKE_UPDATED_AT`),
with a Streamlit UI (direct lookup / Cortex Agents).

After install:
```sql
GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION <app>;
GRANT USAGE ON WAREHOUSE <wh> TO APPLICATION <app>;
CALL <app>.api.init('<wh>');   -- initial load + sync task + in-app agent
```
Then open the Streamlit `API.DEMO_UI`.
