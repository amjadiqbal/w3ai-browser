import React, { useEffect } from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type { TransactionDetail } from "../../shared/types";
import StatusChip from "../components/StatusChip";

export default function HistoryScreen() {
  const state = useAppState();
  const dispatch = useDispatch();

  useEffect(() => {
    dispatch({ type: "SET_HISTORY_LOADING", payload: true });
    sendMessage<TransactionDetail[]>("GET_HISTORY", { page: 1, limit: 50 })
      .then((h) => dispatch({ type: "SET_HISTORY", payload: h }))
      .catch(() => dispatch({ type: "SET_HISTORY_LOADING", payload: false }));
  }, [dispatch]);

  return (
    <div className="screen" style={{ padding: 0, gap: 0 }}>
      <header className="screen-header">
        <button className="btn btn-ghost" onClick={() => dispatch({ type: "SET_SCREEN", payload: "swap" })} aria-label="Back">←</button>
        <span className="screen-title">History</span>
      </header>

      <div style={{ overflowY: "auto", flex: 1 }}>
        {state.historyLoading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="history-item">
              <div className="skeleton" style={{ width: 36, height: 36, borderRadius: "50%" }} />
              <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--space-1)" }}>
                <div className="skeleton" style={{ width: 100, height: 14 }} />
                <div className="skeleton" style={{ width: 70, height: 11 }} />
              </div>
            </div>
          ))
        ) : state.history.length === 0 ? (
          <div style={{ textAlign: "center", padding: "var(--space-8)", color: "var(--text-tertiary)" }}>
            No swaps yet.
          </div>
        ) : (
          state.history.map((tx) => (
            <div
              key={tx.id}
              className="history-item"
              role="button"
              tabIndex={0}
              onClick={() => {
                dispatch({ type: "SET_SELECTED_TX", payload: tx });
                dispatch({ type: "SET_SCREEN", payload: "transaction-detail" });
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  dispatch({ type: "SET_SELECTED_TX", payload: tx });
                  dispatch({ type: "SET_SCREEN", payload: "transaction-detail" });
                }
              }}
              aria-label={`${tx.from} to ${tx.to}, status ${tx.status}`}
            >
              <div style={{ display: "flex", flexDirection: "column", flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: "var(--font-size-base)" }}>
                  {tx.from?.toUpperCase()} → {tx.to?.toUpperCase()}
                </div>
                <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>
                  {new Date(tx.createdAt).toLocaleDateString()}
                </div>
              </div>
              <StatusChip status={tx.status} />
              <span style={{ color: "var(--text-tertiary)", fontSize: "var(--font-size-sm)" }}>›</span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
