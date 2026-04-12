import React, { useEffect, useState } from "react";

interface Props {
  expiresAt: number;
  onExpired: () => void;
}

export default function QuoteCountdown({ expiresAt, onExpired }: Props) {
  const [remaining, setRemaining] = useState(Math.max(0, expiresAt - Date.now()));

  useEffect(() => {
    if (remaining <= 0) {
      onExpired();
      return;
    }
    const id = setInterval(() => {
      const left = Math.max(0, expiresAt - Date.now());
      setRemaining(left);
      if (left <= 0) {
        clearInterval(id);
        onExpired();
      }
    }, 1000);
    return () => clearInterval(id);
  }, [expiresAt, onExpired]);

  const seconds = Math.ceil(remaining / 1000);
  const warning = seconds <= 10;

  return (
    <div
      style={{
        fontSize: "var(--font-size-xs)",
        color: warning ? "var(--accent-warning)" : "var(--text-tertiary)",
        fontVariantNumeric: "tabular-nums",
        display: "flex",
        alignItems: "center",
        gap: "var(--space-1)",
      }}
      aria-live="polite"
      aria-atomic="true"
    >
      <span>Quote expires in</span>
      <strong style={{ color: warning ? "var(--accent-warning)" : "var(--text-secondary)" }}>
        {seconds}s
      </strong>
    </div>
  );
}
