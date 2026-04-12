import React from "react";
import { useAppState, useDispatch } from "../state/AppStore";

export default function ErrorScreen() {
  const state = useAppState();
  const dispatch = useDispatch();

  return (
    <div className="screen" style={{ alignItems: "center", justifyContent: "center", textAlign: "center" }}>
      <div style={{ fontSize: 48 }}>⚠️</div>
      <h2 style={{ fontSize: "var(--font-size-lg)", fontWeight: 700 }}>Something went wrong</h2>
      <p style={{ color: "var(--text-secondary)", fontSize: "var(--font-size-sm)", maxWidth: 280 }}>
        {state.error?.message ?? "An unexpected error occurred. Please try again."}
      </p>
      <button
        className="btn btn-primary"
        onClick={() => {
          dispatch({ type: "CLEAR_ERROR" });
          dispatch({ type: "SET_SCREEN", payload: "swap" });
        }}
      >
        Try Again
      </button>
    </div>
  );
}
