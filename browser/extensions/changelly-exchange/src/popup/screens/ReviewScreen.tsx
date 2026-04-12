/**
 * Review transaction screen — shows rate, fees, recipient, and confirmation CTA.
 */

import React, { useEffect, useRef, useState } from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type {
  AddressValidationResult,
  SwapExecutionState,
  ApiError,
} from "../../shared/types";
import FeeBreakdownRow from "../components/FeeBreakdownRow";
import QuoteCountdown from "../components/QuoteCountdown";

export default function ReviewScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const [address, setAddress] = useState(state.draft.recipientAddress);
  const [extraId, setExtraId] = useState(state.draft.recipientExtraId ?? "");
  const [validation, setValidation] = useState<AddressValidationResult | null>(null);
  const [validating, setValidating] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<ApiError | null>(null);
  const [termsAck, setTermsAck] = useState(false);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const toAsset = state.assets.find((a) => a.id === state.draft.to);
  const fromAsset = state.assets.find((a) => a.id === state.draft.from);
  const quote = state.quote;

  function onAddressChange(e: React.ChangeEvent<HTMLInputElement>) {
    const val = e.target.value;
    setAddress(val);
    setValidation(null);
    dispatch({ type: "SET_DRAFT", payload: { recipientAddress: val } });

    if (debounce.current) clearTimeout(debounce.current);
    if (!val) return;
    debounce.current = setTimeout(async () => {
      setValidating(true);
      try {
        const res = await sendMessage<AddressValidationResult>("VALIDATE_ADDRESS", {
          address: val,
          currency: state.draft.to,
          extraId: extraId || undefined,
        });
        setValidation(res);
      } catch {
        setValidation({ address: val, currency: state.draft.to, result: false, message: "Validation failed." });
      } finally {
        setValidating(false);
      }
    }, 600);
  }

  async function handleConfirm() {
    if (!quote || !address || !termsAck) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      const resp = await sendMessage<{ result: unknown; state: SwapExecutionState }>("CREATE_SWAP", {
        from: state.draft.from,
        to: state.draft.to,
        amount: state.draft.amountFrom,
        address,
        extraId: extraId || undefined,
        rateType: state.draft.rateType,
        rateId: quote.type === "fixed" ? quote.rateId : undefined,
      });
      dispatch({ type: "SET_CURRENT_SWAP", payload: resp.state });
      dispatch({ type: "SET_SCREEN", payload: "pending" });
    } catch (err) {
      setSubmitError(err as ApiError);
    } finally {
      setSubmitting(false);
    }
  }

  const addressInvalid = validation && !validation.result;
  const canConfirm =
    address &&
    !addressInvalid &&
    !validating &&
    termsAck &&
    !submitting &&
    quote;

  if (!quote) {
    dispatch({ type: "SET_SCREEN", payload: "swap" });
    return null;
  }

  return (
    <div className="screen">
      <header className="screen-header">
        <button className="btn btn-ghost" onClick={() => dispatch({ type: "SET_SCREEN", payload: "swap" })} aria-label="Back">
          ←
        </button>
        <span className="screen-title">Review Swap</span>
      </header>

      {/* Summary card */}
      <div className="card-elevated" style={{ display: "flex", flexDirection: "column", gap: "var(--space-3)" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontSize: "var(--font-size-xl)", fontWeight: 700 }}>
              {state.draft.amountFrom} <span style={{ color: "var(--text-secondary)" }}>{fromAsset?.symbol}</span>
            </div>
            <div style={{ fontSize: "var(--font-size-sm)", color: "var(--text-tertiary)" }}>You send</div>
          </div>
          <div style={{ color: "var(--accent-primary)", fontSize: "var(--font-size-xl)" }}>→</div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: "var(--font-size-xl)", fontWeight: 700 }}>
              {quote.type === "fixed" ? quote.amountTo : quote.estimatedAmountTo}{" "}
              <span style={{ color: "var(--text-secondary)" }}>{toAsset?.symbol}</span>
            </div>
            <div style={{ fontSize: "var(--font-size-sm)", color: "var(--text-tertiary)" }}>
              {quote.type === "fixed" ? "Guaranteed" : "Estimated"}
            </div>
          </div>
        </div>

        <div style={{ borderTop: "1px solid var(--border-subtle)", paddingTop: "var(--space-3)", display: "flex", flexDirection: "column", gap: "var(--space-2)" }}>
          <FeeBreakdownRow label="Exchange rate" value={`1 ${fromAsset?.symbol} ≈ ${quote.rate.toFixed(6)} ${toAsset?.symbol}`} />
          <FeeBreakdownRow label="Network fee" value={`${quote.networkFee} ${toAsset?.symbol}`} />
          <FeeBreakdownRow label="Rate type" value={quote.type === "fixed" ? "Fixed (locked)" : "Floating (market)"} />
        </div>

        <QuoteCountdown
          expiresAt={quote.expiresAt}
          onExpired={() => dispatch({ type: "SET_SCREEN", payload: "swap" })}
        />
      </div>

      {/* Recipient address */}
      <div>
        <label
          htmlFor="recipient-address"
          style={{ display: "block", fontSize: "var(--font-size-sm)", color: "var(--text-secondary)", marginBottom: "var(--space-2)" }}
        >
          {toAsset?.name ?? "Destination"} address
        </label>
        <input
          id="recipient-address"
          className={`input-field${addressInvalid ? " error" : ""}`}
          placeholder={`Paste your ${toAsset?.symbol ?? "destination"} address`}
          value={address}
          onChange={onAddressChange}
          autoComplete="off"
          spellCheck={false}
          aria-describedby={addressInvalid ? "address-error" : undefined}
          aria-invalid={addressInvalid ?? undefined}
        />
        {validating && (
          <div style={{ marginTop: "var(--space-1)", fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>
            Validating address…
          </div>
        )}
        {addressInvalid && (
          <div id="address-error" role="alert" style={{ marginTop: "var(--space-1)", fontSize: "var(--font-size-xs)", color: "var(--accent-danger)" }}>
            {validation?.message ?? "Invalid address for this network."}
          </div>
        )}
        {validation?.result && (
          <div style={{ marginTop: "var(--space-1)", fontSize: "var(--font-size-xs)", color: "var(--accent-success)" }}>
            Address verified ✓
          </div>
        )}
      </div>

      {/* Extra ID (memo/tag) if required */}
      {toAsset?.requiresExtraId && (
        <div>
          <label
            htmlFor="extra-id"
            style={{ display: "block", fontSize: "var(--font-size-sm)", color: "var(--text-secondary)", marginBottom: "var(--space-2)" }}
          >
            {toAsset.extraIdName ?? "Memo / Tag"} (required)
          </label>
          <input
            id="extra-id"
            className="input-field"
            placeholder={`Enter ${toAsset.extraIdName ?? "memo"}`}
            value={extraId}
            onChange={(e) => {
              setExtraId(e.target.value);
              dispatch({ type: "SET_DRAFT", payload: { recipientExtraId: e.target.value } });
            }}
          />
        </div>
      )}

      {/* Terms notice */}
      <div className="banner banner-info" style={{ fontSize: "var(--font-size-xs)" }}>
        By proceeding you agree to the{" "}
        <a href={state.config.termsUrl} target="_blank" rel="noopener noreferrer" style={{ color: "inherit", fontWeight: 600 }}>
          Terms of Service
        </a>{" "}
        and{" "}
        <a href={state.config.privacyUrl} target="_blank" rel="noopener noreferrer" style={{ color: "inherit", fontWeight: 600 }}>
          Privacy Policy
        </a>. Changelly may apply AML/KYC checks. Rates are estimates and may vary.
      </div>

      <label style={{ display: "flex", gap: "var(--space-2)", alignItems: "center", fontSize: "var(--font-size-sm)", cursor: "pointer" }}>
        <input type="checkbox" checked={termsAck} onChange={(e) => setTermsAck(e.target.checked)} />
        <span style={{ color: "var(--text-secondary)" }}>I understand and accept the terms</span>
      </label>

      {submitError && (
        <div className="banner banner-danger" role="alert">{submitError.message}</div>
      )}

      <button className="btn btn-primary" disabled={!canConfirm} onClick={handleConfirm}>
        {submitting ? "Submitting…" : "Confirm Swap"}
      </button>
    </div>
  );
}
