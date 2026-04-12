/**
 * Token picker screen — searchable list of available currencies.
 */

import React, { useMemo, useState } from "react";
import { useAppState, useDispatch } from "../state/AppStore";

interface Props {
  side: "from" | "to";
}

export default function TokenPickerScreen({ side }: Props) {
  const state = useAppState();
  const dispatch = useDispatch();
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return state.assets
      .filter((a) => a.enabled)
      .filter(
        (a) =>
          !q ||
          a.symbol.toLowerCase().includes(q) ||
          a.name.toLowerCase().includes(q) ||
          a.fullName.toLowerCase().includes(q)
      )
      .slice(0, 80);
  }, [state.assets, search]);

  function select(id: string) {
    if (side === "from") {
      if (id === state.draft.to) {
        dispatch({ type: "SET_DRAFT", payload: { from: id, to: state.draft.from } });
      } else {
        dispatch({ type: "SET_DRAFT", payload: { from: id } });
      }
    } else {
      if (id === state.draft.from) {
        dispatch({ type: "SET_DRAFT", payload: { to: id, from: state.draft.to } });
      } else {
        dispatch({ type: "SET_DRAFT", payload: { to: id } });
      }
    }
    dispatch({ type: "SET_QUOTE", payload: null });
    dispatch({ type: "SET_SCREEN", payload: "swap" });
  }

  return (
    <div className="screen" style={{ padding: 0, gap: 0 }}>
      <header className="screen-header" style={{ padding: "var(--space-3) var(--space-4)" }}>
        <button
          className="btn btn-ghost"
          onClick={() => dispatch({ type: "SET_SCREEN", payload: "swap" })}
          aria-label="Back"
        >
          ←
        </button>
        <span className="screen-title">Select {side === "from" ? "Source" : "Destination"} Token</span>
      </header>

      <div style={{ padding: "var(--space-3) var(--space-4)" }}>
        <input
          className="input-field"
          placeholder="Search by name or symbol…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          autoFocus
          aria-label="Search tokens"
        />
      </div>

      <div style={{ overflowY: "auto", flex: 1 }}>
        {state.assetsLoading ? (
          Array.from({ length: 8 }).map((_, i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", padding: "var(--space-3) var(--space-4)", borderBottom: "1px solid var(--border-subtle)" }}>
              <div className="skeleton" style={{ width: 32, height: 32, borderRadius: "50%" }} />
              <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--space-1)" }}>
                <div className="skeleton" style={{ width: 60, height: 14 }} />
                <div className="skeleton" style={{ width: 100, height: 11 }} />
              </div>
            </div>
          ))
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: "center", padding: "var(--space-8)", color: "var(--text-tertiary)" }}>
            No assets found.
          </div>
        ) : (
          filtered.map((asset) => {
            const selected = side === "from" ? asset.id === state.draft.from : asset.id === state.draft.to;
            return (
              <button
                key={asset.id}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "var(--space-3)",
                  padding: "var(--space-3) var(--space-4)",
                  borderBottom: "1px solid var(--border-subtle)",
                  width: "100%",
                  background: selected ? "var(--accent-primary-muted)" : "transparent",
                  border: "none",
                  cursor: "pointer",
                  textAlign: "left",
                  transition: "background var(--transition-fast)",
                }}
                onClick={() => select(asset.id)}
                aria-pressed={selected}
                aria-label={`${asset.fullName} (${asset.symbol})`}
                onMouseEnter={(e) => {
                  if (!selected) (e.currentTarget as HTMLButtonElement).style.background = "var(--surface-hover)";
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.background = selected ? "var(--accent-primary-muted)" : "transparent";
                }}
              >
                {asset.iconUrl ? (
                  <img
                    src={asset.iconUrl}
                    alt=""
                    aria-hidden
                    style={{ width: 32, height: 32, borderRadius: "50%", objectFit: "cover", flexShrink: 0 }}
                    onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
                  />
                ) : (
                  <div style={{ width: 32, height: 32, borderRadius: "50%", background: "var(--surface-elevated)", flexShrink: 0, display: "flex", alignItems: "center", justifyContent: "center", fontSize: "var(--font-size-xs)", color: "var(--text-secondary)", fontWeight: 700 }}>
                    {asset.symbol.slice(0, 2)}
                  </div>
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: "var(--font-size-base)", color: "var(--text-primary)" }}>
                    {asset.symbol}
                  </div>
                  <div style={{ fontSize: "var(--font-size-xs)", color: "var(--text-tertiary)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {asset.fullName}
                  </div>
                </div>
                {selected && (
                  <span style={{ color: "var(--accent-primary)", fontSize: "var(--font-size-xs)" }}>✓</span>
                )}
              </button>
            );
          })
        )}
      </div>
    </div>
  );
}
