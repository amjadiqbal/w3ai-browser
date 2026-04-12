import React from "react";

interface Props {
  label: string;
  value: string;
  faint?: boolean;
}

export default function FeeBreakdownRow({ label, value, faint }: Props) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", fontSize: "var(--font-size-sm)" }}>
      <span style={{ color: "var(--text-tertiary)" }}>{label}</span>
      <span style={{ color: faint ? "var(--text-tertiary)" : "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>
        {value}
      </span>
    </div>
  );
}
