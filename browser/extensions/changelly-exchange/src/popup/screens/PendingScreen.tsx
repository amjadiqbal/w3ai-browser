/**
 * Pending / live tracking screen.
 * Polls background for status updates and renders appropriate state.
 */

import React, { useEffect, useState } from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import { sendMessage } from "../messaging";
import type { SwapStatus, TransactionStatus } from "../../shared/types";
import StatusChip from "../components/StatusChip";
import CopyButton from "../components/CopyButton";
import { STATUS_POLL_INTERVAL_MS } from "../../config/env";

const STATUS_MESSAGES: Record<SwapStatus, string> = {
  new: "Swap created — waiting for deposit.",
  waiting: "Waiting for your deposit…",
  confirming: "Confirming your deposit on-chain…",
  exchanging: "Exchanging your funds…",
  sending: "Sending to your address…",
  finished: "Swap complete!",
  failed: "Swap failed. Please contact support.",
  refunded: "Funds have been refunded to the deposit address.",
  hold: "Your swap is on hold — Changelly may contact you.",
  expired: "Swap expired. Please start a new swap.",
  overdue: "Deposit received after the deadline.",
};

export default function PendingScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const swap = state.currentSwap;
  const [copied, setCopied] = useState(false);

  const terminal: SwapStatus[] = ["finished", "failed", "refunded", "expired", "overdue"];

  // Poll status when on this screen
  useEffect(() => {
    if (!swap) return;
    if (terminal.includes(swap.status)) return;

    const interval = setInterval(async () => {
      try {
        const status = await sendMessage<TransactionStatus>("GET_SWAP_STATUS", { id: swap.id });
        dispatch({ type: "UPDATE_SWAP_STATUS", payload: { status: status.status, updatedAt: status.updatedAt } });

        if (terminal.includes(status.status)) {
          clearInterval(interval);
          if (status.status === "finished") {
            dispatch({ type: "SET_SCREEN", payload: "receipt" });
          }
        }
      } catch {
        /* ignore transient failures */
      }
    }, STATUS_POLL_INTERVAL_MS);

    return () => clearInterval(interval);
  }, [swap?.id, swap?.status, dispatch]);

  if (!swap) {
    dispatch({ type: "SET_SCREEN", payload: "swap" });
    return null;
  }

  const isTerminal = terminal.includes(swap.status);
  const isHold = swap.status === "hold";

  return (
    <div className="screen">
      <header className="screen-header">
        <span className="screen-title">Swap Status</span>
        {isTerminal && (
          <button
            className="btn btn-ghost"
            onClick={() => {
              dispatch({ type: "RESET_DRAFT" });
              dispatch({ type: "SET_SCREEN", payload: "swap" });
            }}
          >
            New Swap
          </button>
        )}
      </header>

      {/* Status card */}
      <div className="card-elevated" style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", alignItems: "center", textAlign: "center", padding: "var(--space-6)" }}>
        <StatusChip status={swap.status} large />
        <p style={{ fontSize: "var(--font-size-md)", color: "var(--text-secondary)" }}>
          {STATUS_MESSAGES[swap.status]}
        </p>

        {isHold && (
          <a
            href={state.config.changellySupportUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-ghost"
            style={{ fontSize: "var(--font-size-sm)" }}
          >
            Contact Changelly Support →
          </a>
        )}

        {swap.status === "finished" && (
          <div style={{ color: "var(--accent-success)", fontSize: "var(--font-size-xl)", fontWeight: 700 }}>
            {swap.expectedAmountTo} {swap.to.toUpperCase()}
          </div>
        )}
      </div>

      {/* Deposit address */}
      {!isTerminal && swap.status !== "hold" && (
        <div>
          <div style={{ fontSize: "var(--font-size-sm)", color: "var(--text-secondary)", marginBottom: "var(--space-2)" }}>
            Send exactly{" "}
            <strong>{swap.expectedAmountFrom} {swap.from.toUpperCase()}</strong> to:
          </div>
          <div className="address-copy-block">
            <span className="address-text">{swap.payinAddress}</span>
            <CopyButton text={swap.payinAddress} />
          </div>
          {swap.payinExtraId && (
            <div style={{ marginTop: "var(--space-3)" }}>
              <div style={{ fontSize: "var(--font-size-sm)", color: "var(--text-secondary)", marginBottom: "var(--space-2)" }}>
                Memo / Tag (required):
              </div>
              <div className="address-copy-block">
                <span className="address-text">{swap.payinExtraId}</span>
                <CopyButton text={swap.payinExtraId} />
              </div>
            </div>
          )}
          <div className="banner banner-warning" style={{ marginTop: "var(--space-3)" }}>
            ⚠ Only send {swap.from.toUpperCase()} to this address. Sending any other asset may result in permanent loss.
          </div>
        </div>
      )}

      {/* Transaction ID */}
      <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)", wordBreak: "break-all" }}>
        Transaction ID: {swap.id}
      </div>

      {swap.trackingUrl && (
        <a
          href={swap.trackingUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="btn btn-ghost"
          style={{ textAlign: "center", fontSize: "var(--font-size-sm)" }}
        >
          View on Changelly →
        </a>
      )}
    </div>
  );
}
