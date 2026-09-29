-- ============================================================================
-- Consumer account で ACCOUNTADMIN として実行
-- 本ファイルは SQL 版。同じ内容は Snowsight の GUI からも実施可能（下記「Snowsight で実施する場合」参照）
-- ============================================================================
--
-- [Snowsight で実施する場合]
--   1. インストール
--      Snowsight の Private Listing 一覧（例: Catalog / Data sharing の「Shared with you」等。
--      メニュー名はリリースにより異なる場合あり）から "Demo Hybrid Lookup PoC" を開き [Get]。
--      アプリ名（例: DEMO_HT_APP）とウェアハウスを指定してインストール
--      ※ SQL の手順 1 に相当
--   2. 権限付与
--      インストール後、アプリのページで manifest が要求する権限
--      （EXECUTE TASK / EXECUTE MANAGED TASK）を [Grant]。
--      ウェアハウスの USAGE は、ワークシートで手順 2 の 2 行目の GRANT を実行
--      ※ SQL の手順 2 に相当
--   3. 初期化
--      ワークシートで手順 3 の CALL ... init('<WH名>') を実行
--   4. 利用
--      Apps 一覧から DEMO_HT_APP を開き、Streamlit (DEMO_UI) を起動
--      タブ①: Hybrid table 直接参照 / タブ②: Cortex Agents 経由
-- ============================================================================

USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60;
USE WAREHOUSE COMPUTE_WH;

-- 1. リスティングからアプリをインストール（Snowsight: リスティングの [Get]）
CREATE APPLICATION DEMO_HT_APP FROM LISTING <LISTING_GLOBAL_NAME>;

-- 2. 権限付与（Snowsight: アプリのページで [Grant]。WH の USAGE は SQL で実行）
GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION DEMO_HT_APP;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO APPLICATION DEMO_HT_APP;

-- 3. 初期ロード + 同期タスク開始 + アプリ内 Agent 作成
CALL DEMO_HT_APP.api.init('COMPUTE_WH');

-- 4. 動作確認（Snowsight: Apps » DEMO_HT_APP » DEMO_UI を開く）
SELECT COUNT(*) FROM DEMO_HT_APP.api.reservation_v;
SHOW STREAMLITS IN APPLICATION DEMO_HT_APP;
