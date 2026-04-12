import React from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type { UserSetting } from "../../shared/types";

type RateType = "floating" | "fixed";

export default function SettingsScreen() {
  const state = useAppState();
  const dispatch = useDispatch();

  async function save(patch: Partial<UserSetting>) {
    const updated: UserSetting = { ...state.settings, ...patch };
    dispatch({ type: "SET_SETTINGS", payload: updated });
    await sendMessage("SAVE_SETTINGS", updated).catch(() => null);
  }

  return (
    <div className="screen">
      <header className="screen-header">
        <button className="btn btn-ghost" onClick={() => dispatch({ type: "SET_SCREEN", payload: "swap" })} aria-label="Back">←</button>
        <span className="screen-title">Settings</span>
      </header>

      <div className="card" style={{ display: "flex", flexDirection: "column", gap: "var(--space-5)" }}>
        {/* Default rate type */}
        <div>
          <div style={{ fontSize: "var(--font-size-sm)", fontWeight: 600, marginBottom: "var(--space-3)" }}>Default Rate Type</div>
          <div style={{ display: "flex", gap: "var(--space-2)" }}>
            {(["floating", "fixed"] as RateType[]).map((t) => (
              <button
                key={t}
                className={`btn ${state.settings.preferredRateType === t ? "btn-primary" : "btn-ghost"}`}
                style={{ flex: 1, textTransform: "capitalize" }}
                onClick={() => save({ preferredRateType: t })}
                disabled={t === "fixed" && !state.featureFlags.fixedRateEnabled}
              >
                {t}
              </button>
            ))}
          </div>
        </div>

        {/* Slippage tolerance (for DeFi swaps) */}
        {state.featureFlags.defiEnabled && (
          <div>
            <div style={{ fontSize: "var(--font-size-sm)", fontWeight: 600, marginBottom: "var(--space-3)" }}>
              Slippage Tolerance: {state.settings.slippageTolerance ?? 0.5}%
            </div>
            <input
              type="range"
              min={0.1}
              max={5}
              step={0.1}
              value={state.settings.slippageTolerance ?? 0.5}
              onChange={(e) => save({ slippageTolerance: parseFloat(e.target.value) })}
              style={{ width: "100%" }}
              aria-label="Slippage tolerance"
            />
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)", marginTop: "var(--space-1)" }}>
              <span>0.1%</span><span>5%</span>
            </div>
          </div>
        )}
      </div>

      {/* Info section */}
      <div className="card" style={{ display: "flex", flexDirection: "column", gap: "var(--space-3)" }}>
        <a href={state.config.termsUrl} target="_blank" rel="noopener noreferrer" style={{ color: "var(--text-link)", fontSize: "var(--font-size-sm)", textDecoration: "none" }}>Terms of Service →</a>
        <a href={state.config.privacyUrl} target="_blank" rel="noopener noreferrer" style={{ color: "var(--text-link)", fontSize: "var(--font-size-sm)", textDecoration: "none" }}>Privacy Policy →</a>
        <a href={state.config.changellySupportUrl} target="_blank" rel="noopener noreferrer" style={{ color: "var(--text-link)", fontSize: "var(--font-size-sm)", textDecoration: "none" }}>Exchange Support →</a>
        <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>
          Exchange services powered by Changelly.
        </div>
      </div>
    </div>
  );
}
