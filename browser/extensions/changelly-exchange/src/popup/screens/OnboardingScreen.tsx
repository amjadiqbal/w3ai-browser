/**
 * Onboarding welcome flow — shown on first install.
 */

import React, { useState } from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type { UserSetting } from "../../shared/types";

const STEPS = [
  {
    icon: "⚡",
    title: "Swap 500+ Cryptocurrencies",
    body: "Exchange Bitcoin, Ethereum, and hundreds more — right from your browser toolbar.",
  },
  {
    icon: "🔒",
    title: "Non-Custodial Exchange",
    body: "We never hold your funds. Swaps go directly to your wallet address.",
  },
  {
    icon: "💡",
    title: "Best Rates, Transparent Fees",
    body: "Choose floating or fixed rates. All fees shown before you confirm — no surprises.",
  },
];

export default function OnboardingScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const [step, setStep] = useState(0);

  async function complete() {
    const updated: UserSetting = { ...state.settings, onboardingCompleted: true, termsAccepted: true };
    await sendMessage("SAVE_SETTINGS", updated).catch(() => null);
    dispatch({ type: "SET_SETTINGS", payload: updated });
    dispatch({ type: "SET_SCREEN", payload: "swap" });
  }

  const current = STEPS[step];
  const isLast = step === STEPS.length - 1;

  return (
    <div className="screen" style={{ justifyContent: "space-between", minHeight: 480 }}>
      {/* Skip */}
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button className="btn btn-ghost" style={{ fontSize: "var(--font-size-sm)" }} onClick={complete}>
          Skip
        </button>
      </div>

      {/* Slide content */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "var(--space-5)", textAlign: "center", padding: "var(--space-6)" }}>
        <div style={{ fontSize: 56 }}>{current.icon}</div>
        <h1 style={{ fontSize: "var(--font-size-xl)", fontWeight: 700, color: "var(--text-primary)" }}>
          {current.title}
        </h1>
        <p style={{ fontSize: "var(--font-size-md)", color: "var(--text-secondary)", lineHeight: 1.5 }}>
          {current.body}
        </p>
      </div>

      {/* Step dots */}
      <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        {STEPS.map((_, i) => (
          <div
            key={i}
            style={{
              width: i === step ? 20 : 6,
              height: 6,
              borderRadius: "var(--radius-full)",
              background: i === step ? "var(--accent-primary)" : "var(--border-default)",
              transition: "width 0.2s ease, background 0.2s ease",
            }}
          />
        ))}
      </div>

      {/* Legal notice on last step */}
      {isLast && (
        <p style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)", textAlign: "center", padding: "0 var(--space-4)", marginBottom: "var(--space-3)" }}>
          By continuing you agree to our{" "}
          <a href={state.config.termsUrl} target="_blank" rel="noopener noreferrer" style={{ color: "var(--text-link)" }}>Terms</a>
          {" "}and{" "}
          <a href={state.config.privacyUrl} target="_blank" rel="noopener noreferrer" style={{ color: "var(--text-link)" }}>Privacy Policy</a>.
          Exchange services provided by Changelly.
        </p>
      )}

      <button
        className="btn btn-primary"
        onClick={() => isLast ? complete() : setStep((s) => s + 1)}
        style={{ margin: "0 var(--space-4) var(--space-4)" }}
      >
        {isLast ? "Get Started" : "Next"}
      </button>
    </div>
  );
}
