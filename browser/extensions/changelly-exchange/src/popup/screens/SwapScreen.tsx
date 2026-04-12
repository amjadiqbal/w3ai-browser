/**
 * Swap home screen — the primary exchange widget.
 */

import React, { useCallback, useEffect, useRef, useState } from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type { Quote, TradingPair, ApiError } from "../../shared/types";
import { QUOTE_DEBOUNCE_MS } from "../../config/env";
import StatusChip from "../components/StatusChip";
import FeeBreakdownRow from "../components/FeeBreakdownRow";
import QuoteCountdown from "../components/QuoteCountdown";
import Skeleton from "../components/Skeleton";

export default function SwapScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [pair, setPair] = useState<TradingPair | null>(null);
  const [amountStr, setAmountStr] = useState(
    state.draft.amountFrom > 0 ? String(state.draft.amountFrom) : ""
  );

  const fromAsset = state.assets.find((a) => a.id === state.draft.from);
  const toAsset = state.assets.find((a) => a.id === state.draft.to);

  // Fetch pair info when from/to changes
  useEffect(() => {
    if (!state.draft.from || !state.draft.to) return;
    sendMessage<TradingPair>("GET_PAIRS", { from: state.draft.from, to: state.draft.to })
      .then(setPair)
      .catch(() => setPair(null));
  }, [state.draft.from, state.draft.to]);

  // Debounced quote fetch
  const fetchQuote = useCallback(
    (amount: number) => {
      if (!amount || amount <= 0) {
        dispatch({ type: "SET_QUOTE", payload: null });
        return;
      }
      dispatch({ type: "SET_QUOTE_LOADING", payload: true });

      sendMessage<Quote>("GET_QUOTE", {
        from: state.draft.from,
        to: state.draft.to,
        amount,
        rateType: state.draft.rateType,
      })
        .then((q) => dispatch({ type: "SET_QUOTE", payload: q }))
        .catch((err: ApiError) => dispatch({ type: "SET_QUOTE_ERROR", payload: err }));
    },
    [state.draft.from, state.draft.to, state.draft.rateType, dispatch]
  );

  function handleAmountChange(e: React.ChangeEvent<HTMLInputElement>) {
    const val = e.target.value;
    if (!/^\d*\.?\d*$/.test(val)) return;
    setAmountStr(val);
    const num = parseFloat(val);
    dispatch({ type: "SET_DRAFT", payload: { amountFrom: isNaN(num) ? 0 : num } });

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => fetchQuote(isNaN(num) ? 0 : num), QUOTE_DEBOUNCE_MS);
  }

  function swapDirections() {
    dispatch({
      type: "SET_DRAFT",
      payload: { from: state.draft.to, to: state.draft.from },
    });
    dispatch({ type: "SET_QUOTE", payload: null });
    setAmountStr("");
  }

  function toggleRateType() {
    const next = state.draft.rateType === "floating" ? "fixed" : "floating";
    dispatch({ type: "SET_DRAFT", payload: { rateType: next } });
    dispatch({ type: "SET_QUOTE", payload: null });
    if (state.draft.amountFrom > 0) {
      fetchQuote(state.draft.amountFrom);
    }
  }

  const canReview =
    state.quote &&
    state.draft.amountFrom > 0 &&
    !state.quoteLoading;

  return (
    <div className="screen">
      <header className="screen-header">
        <span className="screen-title">Exchange</span>
        <button
          className="btn btn-ghost"
          aria-label="History"
          onClick={() => dispatch({ type: "SET_SCREEN", payload: "history" })}
        >
          ⏱
        </button>
        <button
          className="btn btn-ghost"
          aria-label="Settings"
          onClick={() => dispatch({ type: "SET_SCREEN", payload: "settings" })}
        >
          ⚙
        </button>
      </header>

      {/* Rate type toggle */}
      <div style={{ display: "flex", gap: "var(--space-2)" }}>
        <button
          className={`btn ${state.draft.rateType === "floating" ? "btn-primary" : "btn-ghost"}`}
          style={{ flex: 1, padding: "var(--space-2)", fontSize: "var(--font-size-sm)" }}
          onClick={() => state.draft.rateType !== "floating" && toggleRateType()}
        >
          Floating Rate
        </button>
        {state.featureFlags.fixedRateEnabled && (
          <button
            className={`btn ${state.draft.rateType === "fixed" ? "btn-primary" : "btn-ghost"}`}
            style={{ flex: 1, padding: "var(--space-2)", fontSize: "var(--font-size-sm)" }}
            onClick={() => state.draft.rateType !== "fixed" && toggleRateType()}
          >
            Fixed Rate
          </button>
        )}
      </div>

      {/* From block */}
      <div className="swap-amount-block">
        <div className="swap-label">You send</div>
        <div className="swap-amount-row">
          <input
            className="swap-amount-input"
            inputMode="decimal"
            placeholder="0"
            value={amountStr}
            onChange={handleAmountChange}
            aria-label="Amount to send"
          />
          <button
            className="token-selector"
            onClick={() => dispatch({ type: "SET_SCREEN", payload: "token-picker-from" })}
            aria-label={`Select from token, currently ${fromAsset?.symbol ?? state.draft.from}`}
          >
            {fromAsset?.iconUrl && (
              <img className="token-icon" src={fromAsset.iconUrl} alt="" aria-hidden />
            )}
            <span className="token-symbol">{fromAsset?.symbol ?? state.draft.from.toUpperCase()}</span>
            <span style={{ color: "var(--text-tertiary)", fontSize: "var(--font-size-xs)" }}>▾</span>
          </button>
        </div>
        {pair && (
          <div style={{ marginTop: "var(--space-2)", fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>
            Min: {pair.minAmount} · Max: {pair.maxAmount}
          </div>
        )}
      </div>

      {/* Swap direction button */}
      <div className="swap-divider">
        <button
          className="swap-arrow-btn"
          onClick={swapDirections}
          aria-label="Swap direction"
        >
          ↕
        </button>
      </div>

      {/* To block */}
      <div className="swap-amount-block">
        <div className="swap-label">You receive</div>
        <div className="swap-amount-row">
          <div style={{ flex: 1, fontSize: "var(--font-size-2xl)", fontWeight: 700, color: state.quoteLoading ? "var(--text-tertiary)" : "var(--text-primary)" }}>
            {state.quoteLoading ? (
              <span className="skeleton" style={{ width: 120, height: 32, display: "block" }} />
            ) : state.quote ? (
              state.quote.type === "fixed"
                ? state.quote.amountTo.toFixed(8).replace(/\.?0+$/, "")
                : state.quote.estimatedAmountTo.toFixed(8).replace(/\.?0+$/, "")
            ) : "—"}
          </div>
          <button
            className="token-selector"
            onClick={() => dispatch({ type: "SET_SCREEN", payload: "token-picker-to" })}
            aria-label={`Select to token, currently ${toAsset?.symbol ?? state.draft.to}`}
          >
            {toAsset?.iconUrl && (
              <img className="token-icon" src={toAsset.iconUrl} alt="" aria-hidden />
            )}
            <span className="token-symbol">{toAsset?.symbol ?? state.draft.to.toUpperCase()}</span>
            <span style={{ color: "var(--text-tertiary)", fontSize: "var(--font-size-xs)" }}>▾</span>
          </button>
        </div>
      </div>

      {/* Quote info */}
      {state.quote && !state.quoteLoading && (
        <div className="card" style={{ gap: "var(--space-2)", display: "flex", flexDirection: "column" }}>
          <FeeBreakdownRow
            label="Rate"
            value={`1 ${state.draft.from.toUpperCase()} ≈ ${state.quote.rate.toFixed(6)} ${state.draft.to.toUpperCase()}`}
          />
          <FeeBreakdownRow
            label="Network fee"
            value={`${state.quote.networkFee} ${state.draft.to.toUpperCase()}`}
          />
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <QuoteCountdown expiresAt={state.quote.expiresAt} onExpired={() => fetchQuote(state.draft.amountFrom)} />
            {state.quote.type === "fixed" && (
              <span style={{ fontSize: "var(--font-size-xs)", color: "var(--accent-success)" }}>Rate locked</span>
            )}
          </div>
        </div>
      )}

      {/* Error */}
      {state.quoteError && (
        <div className="banner banner-danger" role="alert">
          {state.quoteError.message}
        </div>
      )}

      {/* CTA */}
      <button
        className="btn btn-primary"
        disabled={!canReview}
        onClick={() => dispatch({ type: "SET_SCREEN", payload: "review" })}
      >
        {state.quoteLoading ? "Getting rate…" : "Review Swap"}
      </button>
    </div>
  );
}
