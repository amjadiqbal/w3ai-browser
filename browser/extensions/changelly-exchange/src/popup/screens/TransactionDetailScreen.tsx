import React from "react";
import { useAppState, useDispatch } from "../state/AppStore";
import StatusChip from "../components/StatusChip";
import CopyButton from "../components/CopyButton";

export default function TransactionDetailScreen() {
  const state = useAppState();
  const dispatch = useDispatch();
  const tx = state.selectedTransaction;

  if (!tx) {
    dispatch({ type: "SET_SCREEN", payload: "history" });
    return null;
  }

  function row(label: string, value: string | undefined | null, copy = false) {
    if (!value) return null;
    return (
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-1)" }}>
        <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)" }}>{label}</div>
        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", wordBreak: "break-all", fontSize: "var(--font-size-sm)", color: "var(--text-primary)" }}>
          {value}
          {copy && <CopyButton text={value} />}
        </div>
      </div>
    );
  }

  return (
    <div className="screen">
      <header className="screen-header">
        <button className="btn btn-ghost" onClick={() => dispatch({ type: "SET_SCREEN", payload: "history" })} aria-label="Back">←</button>
        <span className="screen-title">Transaction Detail</span>
      </header>

      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ fontSize: "var(--font-size-lg)", fontWeight: 700 }}>
          {tx.from?.toUpperCase()} → {tx.to?.toUpperCase()}
        </div>
        <StatusChip status={tx.status} />
      </div>

      <div className="card" style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
        {row("Transaction ID", tx.id, true)}
        {row("Created", tx.createdAt ? new Date(tx.createdAt).toLocaleString() : undefined)}
        {row("Updated", tx.updatedAt ? new Date(tx.updatedAt).toLocaleString() : undefined)}
        {row("You sent", tx.amountFrom ? `${tx.amountFrom} ${tx.from?.toUpperCase()}` : undefined)}
        {row("You received", tx.amountTo ? `${tx.amountTo} ${tx.to?.toUpperCase()}` : undefined)}
        {row("Destination", tx.recipientAddress, true)}
        {tx.recipientExtraId && row("Memo / Tag", tx.recipientExtraId, true)}
        {row("Deposit address", tx.payinAddress, true)}
        {tx.payinHash && row("Deposit TX hash", tx.payinHash, true)}
        {tx.payoutHash && row("Payout TX hash", tx.payoutHash, true)}
      </div>

      {tx.trackingUrl && (
        <a
          href={tx.trackingUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="btn btn-ghost"
          style={{ textAlign: "center" }}
        >
          View on Changelly →
        </a>
      )}
    </div>
  );
}
