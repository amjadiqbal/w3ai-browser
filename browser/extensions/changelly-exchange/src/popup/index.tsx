/**
 * React popup entry point.
 * Renders the swap widget shell into popup/index.html.
 */

import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles/globals.css";

const container = document.getElementById("root");
if (!container) throw new Error("No #root element");

const viewParam = new URLSearchParams(window.location.search).get("view");
const layout = viewParam === "sidebar" ? "sidebar" : "popup";
document.documentElement.setAttribute("data-layout", layout);

function renderFatal(message: string): void {
  container.innerHTML = `
    <div style="padding:16px;font-family:Arial,sans-serif;color:#edf3ff;background:#050912;min-height:620px;">
      <div style="font-size:12px;letter-spacing:1px;color:#f5a623;font-weight:700;margin-bottom:8px;">POPUP ERROR</div>
      <div style="font-size:14px;line-height:1.4;">${message}</div>
    </div>
  `;
}

window.addEventListener("error", (event) => {
  renderFatal(`Unexpected error: ${event.message}`);
});

window.addEventListener("unhandledrejection", (event) => {
  renderFatal(`Unhandled rejection: ${String(event.reason)}`);
});

try {
  const root = createRoot(container);
  root.render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
} catch (err) {
  renderFatal((err as Error)?.message ?? "Failed to initialize popup.");
}
