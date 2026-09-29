# Snowflake Native App: Shared table → Hybrid table sync (+ Streamlit / Cortex Agents)

プロバイダーが **通常テーブル** を Native App に同梱して共有し、コンシューマー側では **アプリが作成・所有する Hybrid table** に差分同期して OLTP 的なポイント検索に使うサンプルです。
アプリ内の Streamlit から **① Hybrid table 直接参照** と **② Cortex Agents 経由** の2パターンで検索できます。

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
   ├ AGENT.RESERVATION_AGENT Cortex Agent（init 時にアプリが作成）
   └ API.DEMO_UI             Streamlit
        ├ タブ① Hybrid table 直接参照
        └ タブ② Cortex Agents 経由（SNOWFLAKE.CORTEX.DATA_AGENT_RUN）
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
5. Consumer: Snowsight の *Apps* からアプリを開き、Streamlit を起動

### Consumer 側を Snowsight で実施する場合

`04_consumer_install.sql` と同じ内容は、Consumer の Snowsight からも実施できます（メニュー名はリリースにより異なる場合があります）。

| # | Snowsight での操作 | SQL で行う場合 |
|---|---|---|
| 1 | Private Listing（自アカウント向けに共有されたリスティング）を開き **Get** → アプリ名・ウェアハウスを指定してインストール | `CREATE APPLICATION ... FROM LISTING` |
| 2 | アプリのページで、manifest が要求する権限（EXECUTE TASK / EXECUTE MANAGED TASK）を **Grant** | `GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO APPLICATION ...` |
| 3 | ワークシートでウェアハウスの USAGE を付与し、`init` を実行 | `GRANT USAGE ON WAREHOUSE ...` / `CALL <app>.api.init('<wh>')` |
| 4 | *Apps* からアプリを開き Streamlit (`DEMO_UI`) を起動 | - |

※ 手順 3 のウェアハウス付与と `init` は GUI に対応するボタンを用意していないため、ワークシートで実行してください。

## 設計ポイント / 検証で分かった制約

- **Hybrid table は Secure Data Sharing で共有できない**ため、通常テーブルを共有し、コンシューマー側でアプリが Hybrid table を作成する。
- **差分検知はウォーターマーク方式**（`_SNOWFLAKE_UPDATED_AT`）。共有コンテンツへの Stream はマニフェスト共有（Preview）前提のため不採用。5分の重なりを持たせ、MERGE で冪等にしている。
- **Native App 内ではテンポラリテーブルを作成できない**ため、MERGE はサブクエリで直接実行。
- **Cortex Agents のカスタムツール（procedure）は単一セルの戻り値が必要**。表を返すと `expected a single cell result set` エラーになるため、JSON(VARIANT) を返すプロシージャを用意。
- Agent のツール実行にはウェアハウスが必要なため、コンシューマーが `GRANT USAGE ON WAREHOUSE` を付与したうえで `init('<wh>')` 実行時にアプリ内で Agent を作成する。
- テナント分離が必要な場合は、共有ビュー（プロキシビュー）側で行アクセスポリシー等を設計すること。
- Hybrid table の制約（GCP 非対応、DB あたり 2TB、約 16k ops/s など）は公式ドキュメントを参照。

## 参考
- [Native App development workflow](https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-workflow)
- [Share data content in a Snowflake Native App](https://docs.snowflake.com/en/developer-guide/native-apps/preparing-data-content)
- [Hybrid tables limitations](https://docs.snowflake.com/en/user-guide/tables-hybrid-limitations)
- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
