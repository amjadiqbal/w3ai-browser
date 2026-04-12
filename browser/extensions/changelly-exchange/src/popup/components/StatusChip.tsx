import React from "react";
import type { SwapStatus } from "../../shared/types";

const CHIP_STYLES: Record<SwapStatus, { bg: string; color: string; label: string }> = {
  new:        { bg: "var(--status-new-bg)",        color: "var(--status-new-text)",       label: "New" },
  waiting:    { bg: "var(--status-waiting-bg)",    color: "var(--status-waiting-text)",   label: "Waiting" },
  confirming: { bg: "var(--status-confirming-bg)", color: "var(--status-confirming-text)", label: "Confirming" },
  exchanging: { bg: "var(--status-exchanging-bg)", color: "var(--status-exchanging-text)", label: "Exchanging" },
  sending:    { bg: "var(--status-sending-bg)",    color: "var(--status-sending-text)",   label: "Sending" },
  finished:   { bg: "var(--status-finished-bg)",   color: "var(--status-finished-text)",  label: "Finished" },
  failed:     { bg: "var(--status-failed-bg)",      color: "var(--status-failed-text)",    label: "Failed" },
  refunded:   { bg: "var(--status-refunded-bg)",   color: "var(--status-refunded-text)",  label: "Refunded" },
  hold:       { bg: "var(--status-hold-bg)",        color: "var(--status-hold-text)",      label: "On Hold" },
  expired:    { bg: "var(--status-expired-bg)",    color: "var(--status-expired-text)",   label: "Expired" },
  overdue:    { bg: "var(--status-overdue-bg)",    color: "var(--status-overdue-text)",   label: "Overdue" },
};

interface Props {
  status: SwapStatus;
  large?: boolean;
}

export default function StatusChip({ status, large }: Props) {
  const style = CHIP_STYLES[status] ?? CHIP_STYLES.new;
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        borderRadius: "var(--radius-full)",
        padding: large ? "var(--space-2) var(--space-4)" : "2px var(--space-2)",
        fontSize: large ? "var(--font-size-md)" : "var(--font-size-xs)",
        fontWeight: 600,
        background: style.bg,
        color: style.color,
        letterSpacing: "0.01em",
        userSelect: "none",
        whiteSpace: "nowrap",
      }}
    >
      {style.label}
    </span>
  );
}
