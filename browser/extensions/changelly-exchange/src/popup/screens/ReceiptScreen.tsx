import React from "react";
import { useAppState, useDispatch } from "../state/AppStore";

export default function ReceiptScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const swap = state.currentSwap;

  if (!swap) {
    dispatch({ type: "SET_SCREEN", payload: "swap" });
    return null;
  }

  return (
    <div className="screen" style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ textAlign: "center", display: "flex", flexDirection: "column", gap: "var(--space-5)", alignItems: "center" }}>
        <div style={{ fontSize: 64 }}>✅</div>
        <h2 style={{ fontSize: "var(--font-size-xl)", fontWeight: 700 }}>Swap Complete</h2>
        <p style={{ color: "var(--text-secondary)", fontSize: "var(--font-size-md)" }}>
          {swap.expectedAmountTo} <strong>{swap.to.toUpperCase()}</strong> sent to your address.
        </p>
        <div className="address-copy-block" style={{ width: "100%" }}>
          <span className="address-text">{swap.recipientAddress}</span>
        </div>
        <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>
          Transaction ID: {swap.id}
        </div>
      </div>
      <div style={{ display: "flex", gap: "var(--space-3)", width: "100%", marginTop: "auto" }}>
        <button
          className="btn btn-ghost"
          style={{ flex: 1 }}
          onClick={() => dispatch({ type: "SET_SCREEN", payload: "history" })}
        >
          View History
        </button>
        <button
          className="btn btn-primary"
          style={{ flex: 1 }}
          onClick={() => {
            dispatch({ type: "RESET_DRAFT" });
            dispatch({ type: "SET_SCREEN", payload: "swap" });
          }}
        >
          New Swap
        </button>
      </div>
    </div>
  );
}
