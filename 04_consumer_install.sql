-- ============================================================================
-- Consumer account で ACCOUNTADMIN として実行
-- 本ファイルは SQL 版。同じ内容は Snowsight の GUI からも実施可能（下記「Snowsight で実施する場合」参照）
-- ============================================================================
--
-- [Snowsight で実施する場合]
--   1. インストール
--      Snowsight の Private Listing 一覧（自アカウント向けに共有されたリスティング。
--      メニュー名はリリースにより異なる場合あり）から "Demo Hybrid Lookup PoC" を開き [Get]。
--      アプリ名（例: DEMO_HT_APP）を指定してインストール                    ※ 手順 1 に相当
--   2. 権限付与
--      アプリのページで manifest が要求する権限（EXECUTE TASK / EXECUTE MANAGED TASK）を [Grant]
--      ウェアハウス作成と USAGE / CALLER USAGE の付与はワークシートで手順 2 を実行
--   3. 初期化: ワークシートで手順 3 の CALL ... init() を実行
--   4. 利用
--      a) Apps 一覧から DEMO_HT_APP を開き Streamlit (DEMO_UI) を起動
--         タブ①: Hybrid table 直接参照 / タブ②: Cortex Agents 経由
--      b) Snowflake CoWork（AI & ML » Agents）に RESERVATION_AGENT が自動表示される
--         （手順 4 のアプリケーションロール付与が必要）
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. リスティングからアプリをインストール（Snowsight: リスティングの [Get]）
CREATE APPLICATION DEMO_HT_APP FROM LISTING <LISTING_GLOBAL_NAME>;

-- 2. 権限付与
--    同期タスク（Snowsight: アプリのページで [Grant] でも可）
GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION DEMO_HT_APP;
--    アプリ内 Agent が使うウェアハウス（名前は setup.sql で HT_APP_WH に固定）
CREATE WAREHOUSE IF NOT EXISTS HT_APP_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
GRANT USAGE        ON WAREHOUSE HT_APP_WH TO APPLICATION DEMO_HT_APP;  -- Streamlit から Agent 呼び出し（アプリの ID）
GRANT CALLER USAGE ON WAREHOUSE HT_APP_WH TO APPLICATION DEMO_HT_APP;  -- CoWork / REST / SQL（制限付き呼び出し元権限）

-- 3. 初期ロード + 同期タスク開始
USE WAREHOUSE HT_APP_WH;
CALL DEMO_HT_APP.api.init();

-- 4. 利用者ロールへの委譲（CoWork / Streamlit を使うロール）
-- GRANT APPLICATION ROLE DEMO_HT_APP.app_user TO ROLE <USER_ROLE>;
-- GRANT USAGE ON WAREHOUSE HT_APP_WH TO ROLE <USER_ROLE>;

-- 5. 動作確認
DESC AGENT DEMO_HT_APP.AGENT.RESERVATION_AGENT;         -- Agent 定義を監査
SELECT COUNT(*) FROM DEMO_HT_APP.api.reservation_v;
SHOW STREAMLITS IN APPLICATION DEMO_HT_APP;
