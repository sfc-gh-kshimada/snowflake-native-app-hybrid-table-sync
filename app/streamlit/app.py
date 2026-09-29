import json
import time

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Demo 予約検索", layout="wide")
session = get_active_session()
APP = session.sql("SELECT CURRENT_DATABASE()").collect()[0][0]

st.title("Demo 予約検索 (Hybrid table)")

with st.sidebar:
    st.subheader("同期状況")
    try:
        s = session.sql("SELECT * FROM api.sync_status_v").to_pandas()
        st.dataframe(s, hide_index=True)
    except Exception as e:
        st.caption(f"取得失敗: {e}")
    if st.button("今すぐ同期"):
        r = session.sql("CALL api.sync_reservation()").collect()[0][0]
        st.success(r)

tab1, tab2 = st.tabs(["① Hybrid table 直接参照", "② Cortex Agents 経由"])

# ---------- ① direct lookup ----------
with tab1:
    phone = st.text_input("電話番号", value="090-0000-0001", key="phone")
    if st.button("検索", key="search"):
        t0 = time.perf_counter()
        df = session.sql(
            "SELECT reservation_id, customer_name, status, reserved_at, src_updated_at "
            "FROM api.reservation_v WHERE phone_number = ? ORDER BY reserved_at DESC LIMIT 50",
            params=[phone],
        ).to_pandas()
        ms = (time.perf_counter() - t0) * 1000
        st.caption(f"{len(df)} 件 / {ms:.0f} ms (アプリ往復込み)")
        st.dataframe(df, hide_index=True, use_container_width=True)

# ---------- ② via Cortex Agents ----------
def run_agent(question: str, history: list) -> dict:
    """Call app-owned agent via SQL function. Returns {'text':..., 'tools':[...]}"""
    msgs = history + [{"role": "user", "content": [{"type": "text", "text": question}]}]
    req = json.dumps({"messages": msgs})
    raw = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?)",
        params=[f"{APP}.AGENT.RESERVATION_AGENT", req],
    ).collect()[0][0]
    resp = json.loads(raw) if isinstance(raw, str) else raw
    text, tools = [], []
    for c in resp.get("content", []):
        if c.get("type") == "text":
            text.append(c.get("text", ""))
        elif c.get("type") in ("tool_use", "tool_result"):
            tools.append(c)
    return {"text": "\n".join(text), "tools": tools, "raw": resp}


with tab2:
    if "chat" not in st.session_state:
        st.session_state.chat = []
    for m in st.session_state.chat:
        with st.chat_message(m["role"]):
            st.markdown(m["content"][0]["text"])
    q = st.chat_input("例: 090-0000-0001 の予約を最新5件教えて。キャンセル済みはある？")
    if q:
        with st.chat_message("user"):
            st.markdown(q)
        with st.chat_message("assistant"):
            with st.spinner("Agent 実行中..."):
                try:
                    r = run_agent(q, st.session_state.chat)
                    st.markdown(r["text"] or "(回答なし)")
                    with st.expander("ツール呼び出し"):
                        st.json(r["tools"])
                    st.session_state.chat += [
                        {"role": "user", "content": [{"type": "text", "text": q}]},
                        {"role": "assistant", "content": [{"type": "text", "text": r["text"]}]},
                    ]
                except Exception as e:
                    st.error(f"Agent 呼び出しエラー: {e}")
    if st.button("会話をリセット"):
        st.session_state.chat = []
        st.rerun()
