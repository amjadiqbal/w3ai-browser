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
const root = createRoot(container);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
