# Snowflake Native App: Shared table → Hybrid table sync (+ Streamlit / Cortex Agents)

プロバイダーが **通常テーブル** を Native App に同梱して共有し、コンシューマー側では **アプリが作成・所有する Hybrid table** に差分同期して OLTP 的なポイント検索に使うサンプルです。
アプリ内の Streamlit から **① Hybrid table 直接参照** と **② Cortex Agents 経由** の2パターンで検索できます。アプリが作成した Cortex Agent は Consumer の **Snowflake CoWork** にも自動表示されます。

> ⚠️ 検証用のサンプルです。本番利用時は権限・コスト・エラーハンドリングを見直してください。

## アーキテクチャ

```
[Provider account]
  DEMO_POC.PUBLIC_SRC.RESERVATION   … 通常テーブル（例: Openflow PostgreSQL CDC の取り込み先を想定）
     │   _SNOWFLAKE_UPDATED_AT / _SNOWFLAKE_DELETED 列を持つ
     ▼
  Application Package DEMO_HT_PKG ── Private Listing（特定アカウント向け）
                                        │
[Consumer account]                      ▼
  Native App
   ├ CORE.RESERVATION_HT     Hybrid table（PK + セカンダリインデックス）
   ├ CORE.SYNC_TASK          サーバーレスタスク（1分間隔）で差分 MERGE（更新 / 論理削除 / 追加）
   ├ API.LOOKUP_BY_PHONE     表を返すプロシージャ（SQL 利用向け）
   ├ API.LOOKUP_BY_PHONE_JSON  VARIANT を返すプロシージャ（Agent ツール向け）
   ├ AGENT.RESERVATION_AGENT Cortex Agent（setup script でアプリが作成。ツール = LOOKUP_BY_PHONE_JSON）
   │     └ Snowflake CoWork / REST API / SQL(DATA_AGENT_RUN) から利用（制限付き呼び出し元権限）
   └ API.DEMO_UI             Streamlit
        ├ タブ① Hybrid table 直接参照
        └ タブ② Cortex Agents 経由（SNOWFLAKE.CORTEX.DATA_AGENT_RUN、アプリの ID で実行）
```

## ファイル構成

| ファイル | 実行場所 | 内容 |
|---|---|---|
| `01_provider_setup.sql` | Provider | サンプルデータ作成、Application Package と共有コンテンツ設定 |
| `02_provider_build_and_test.sql` | Provider | ファイルアップロード、バージョン登録、**Provider 内でのテストインストール** |
| `03_provider_listing.sql` | Provider | リリースディレクティブ設定、**Private Listing** 公開 |
| `04_consumer_install.sql` | Consumer | リスティングからインストール、権限付与、init（Snowsight でも実施可） |
| `app/manifest.yml` / `app/setup.sql` | - | アプリ本体（Hybrid table、同期、API、Agent、Streamlit） |
| `app/streamlit/app.py` | - | Streamlit UI |

## 手順

1. Provider: `01_provider_setup.sql`
2. Provider: `02_provider_build_and_test.sql`（リポジトリのルートで `snow sql -c <provider> -f 02_provider_build_and_test.sql`）
3. Provider: `03_provider_listing.sql` の `<CONSUMER_ORG>.<CONSUMER_ACCOUNT>` を置き換えて実行
4. Consumer: `04_consumer_install.sql` の `<LISTING_GLOBAL_NAME>` を置き換えて実行（**Snowsight からも実施可能**。下記参照）
5. Consumer: Snowsight の *Apps* からアプリを開き Streamlit を起動、または Snowflake CoWork から `RESERVATION_AGENT` を利用

### Consumer 側を Snowsight で実施する場合

`04_consumer_install.sql` と同じ内容は、Consumer の Snowsight からも実施できます（メニュー名はリリースにより異なる場合があります）。

| # | Snowsight での操作 | SQL で行う場合 |
|---|---|---|
| 1 | Private Listing（自アカウント向けに共有されたリスティング）を開き **Get** → アプリ名を指定してインストール | `CREATE APPLICATION ... FROM LISTING` |
| 2 | アプリのページで、manifest が要求する権限（EXECUTE TASK / EXECUTE MANAGED TASK）を **Grant** | `GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION ...` |
| 3 | ワークシートで `HT_APP_WH` を作成し USAGE / CALLER USAGE、`SNOWFLAKE.CORTEX_USER` を付与、`init()` を実行 | `GRANT USAGE` / `GRANT CALLER USAGE ON WAREHOUSE HT_APP_WH ...` / `GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION ...` / `CALL <app>.api.init()` |
| 4 | 利用者ロールにアプリケーションロールを付与 | `GRANT APPLICATION ROLE <app>.app_user TO ROLE ...` |
| 5 | *Apps* から Streamlit (`DEMO_UI`) を起動、または Snowflake CoWork で `RESERVATION_AGENT` を選択 | - |

※ 手順 3・4 は GUI に対応するボタンを用意していないため、ワークシートで実行してください。

### 既に以前のバージョンを Get 済みの場合

リスティングの再取得は不要です。Provider がリリースディレクティブを更新すると自動でアップグレードされます（Consumer のメンテナンスポリシーにより待機する場合あり）。

```sql
SHOW APPLICATIONS LIKE '<app>';      -- version / patch を確認
ALTER APPLICATION <app> UPGRADE;     -- 既定リリースへ即時アップグレード
```

その後、`04_consumer_install.sql` の手順 2〜4 を実行します（付与済みの GRANT は再実行しても問題ありません）。Hybrid table のデータ・同期状態・同期タスクはバージョン管理外のスキーマにあるため引き継がれます。アプリを DROP して再 Get するとデータも消えるため、通常はアップグレードを推奨します。

## 設計ポイント / 検証で分かった制約

- **Hybrid table は Secure Data Sharing で共有できない**ため、通常テーブルを共有し、コンシューマー側でアプリが Hybrid table を作成する。
- **差分検知はウォーターマーク方式**（`_SNOWFLAKE_UPDATED_AT`）。共有コンテンツへの Stream はマニフェスト共有（Preview）前提のため不採用。5分の重なりを持たせ、MERGE で冪等にしている。
- **Native App 内ではテンポラリテーブルを作成できない**ため、MERGE はサブクエリで直接実行。
- **Cortex Agents のカスタムツール（procedure）は単一セルの戻り値が必要**。表を返すと `expected a single cell result set` エラーになるため、JSON(VARIANT) を返すプロシージャを用意。
- **Agent は setup script で作成**し、ツールは部分修飾名（`api.lookup_by_phone_json`）で指定（アプリ名に依存しない）。ツールの参照先は Agent 作成時には解決されない。
- アプリ作成の Agent は **制限付き呼び出し元権限（RCR）** で動作する。アプリ所有オブジェクト（Hybrid table / プロシージャ）は暗黙の caller grant があるため追加付与は不要。ウェアハウスは Consumer が `GRANT CALLER USAGE`（CoWork / REST / SQL 用）と `GRANT USAGE`（Streamlit からアプリの ID で呼ぶ用）を付与する。
- **Streamlit から Agent を呼ぶ場合はアプリ自身に `SNOWFLAKE.CORTEX_USER` が必要**（`GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION <app>`）。未付与だと `Unknown user-defined function SNOWFLAKE.CORTEX.DATA_AGENT_RUN` になる。CoWork / REST から使う場合は利用者ロール側の権限で動く。
- Agent 定義内のウェアハウス名は固定（`HT_APP_WH`）。Consumer は同名のウェアハウスを用意する。
- Consumer は `DESC AGENT` で Agent 定義を監査でき、feature policy でアプリによる Agent 作成をブロックすることもできる。
- テナント分離が必要な場合は、共有ビュー（プロキシビュー）側で行アクセスポリシー等を設計すること。
- Hybrid table の制約（GCP 非対応、DB あたり 2TB、約 16k ops/s など）は公式ドキュメントを参照。

## Agent Sharing ではなく「Native App 内の Agent」を使う理由

[Agent Sharing](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-sharing)（`GRANT USAGE ON AGENT ... TO SHARE`）では、この構成は実現できません。

| 観点 | Agent Sharing | Native App 内の Agent（本サンプル） |
|---|---|---|
| Agent の所在 | Provider の share | Consumer アカウント内（アプリ所有） |
| ツールの参照先 | Agent と同じ DB で share されたオブジェクトのみ | アプリ所有の Hybrid table（暗黙の caller grant）。GRANT CALLER で Consumer 所有オブジェクトも可 |
| 利用可能なツール | semantic view / Cortex Search / 関数（**procedure 不可**） | 上記に加え procedure、MCP、サンドボックス |
| Consumer 側で作成された Hybrid table の参照 | ✕（Hybrid table は共有不可、Consumer ローカルオブジェクトは参照不可） | ○ |
| Consumer での見え方 | CoWork / REST / SQL | CoWork に自動表示 / REST / SQL |

## 参考
- [Native App development workflow](https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-workflow)
- [Share data content in a Snowflake Native App](https://docs.snowflake.com/en/developer-guide/native-apps/preparing-data-content)
- [Hybrid tables limitations](https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations)
- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Use Cortex Agents and MCP servers in an app](https://docs.snowflake.com/en/developer-guide/native-apps/agents-mcp-servers)
- [Use app-created Cortex Agents and MCP servers (consumer)](https://docs.snowflake.com/en/developer-guide/native-apps/ui-consumer-agents-mcp)
- [Share Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-sharing)
