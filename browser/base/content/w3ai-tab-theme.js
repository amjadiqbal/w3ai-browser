/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * W3Ai Tab-Based Dynamic Theme
 *
 * Cycles through 6 curated gradient palettes as the user switches tabs.
 * Each palette provides a solid base color + gradient for the browser shell,
 * while keeping text and accent legible. Liquid-glass hover effects are
 * applied universally via CSS variables updated here.
 *
 * The palette index is derived from the tab's position index so each tab
 * always gets the same color within a session (deterministic, not random).
 */

const W3AiTabTheme = {
  // 6 carefully chosen gradient palettes — each has a solid base that
  // CleanMyMac-style renders as a rich gradient with glass layers on top.
  PALETTES: [
    {
      // Deep Purple — default
      base: "#0f0820",
      grad: "linear-gradient(160deg, #0f0820 0%, #160d30 30%, #1a0f3d 60%, #221260 100%)",
      surface: "rgba(30, 18, 65, 0.92)",
      surfaceHover: "rgba(42, 24, 88, 0.94)",
      accent: "#a855f7",
      accentGlow: "rgba(168, 85, 247, 0.45)",
      border: "rgba(168, 85, 247, 0.20)",
      toolbar: "rgba(18, 10, 42, 0.92)",
    },
    {
      // Midnight Blue
      base: "#060820",
      grad: "linear-gradient(160deg, #060820 0%, #0c1040 30%, #101860 60%, #142080 100%)",
      surface: "rgba(16, 24, 80, 0.92)",
      surfaceHover: "rgba(22, 32, 100, 0.94)",
      accent: "#60a5fa",
      accentGlow: "rgba(96, 165, 250, 0.45)",
      border: "rgba(96, 165, 250, 0.22)",
      toolbar: "rgba(10, 14, 50, 0.92)",
    },
    {
      // Deep Teal
      base: "#051a18",
      grad: "linear-gradient(160deg, #051a18 0%, #082820 30%, #0a3830 60%, #0d4840 100%)",
      surface: "rgba(10, 40, 35, 0.92)",
      surfaceHover: "rgba(14, 55, 48, 0.94)",
      accent: "#34d399",
      accentGlow: "rgba(52, 211, 153, 0.45)",
      border: "rgba(52, 211, 153, 0.22)",
      toolbar: "rgba(8, 28, 24, 0.92)",
    },
    {
      // Deep Rose
      base: "#1a0818",
      grad: "linear-gradient(160deg, #1a0818 0%, #2a0c28 30%, #380e38 60%, #48104a 100%)",
      surface: "rgba(48, 12, 45, 0.92)",
      surfaceHover: "rgba(64, 16, 60, 0.94)",
      accent: "#f472b6",
      accentGlow: "rgba(244, 114, 182, 0.45)",
      border: "rgba(244, 114, 182, 0.22)",
      toolbar: "rgba(30, 8, 28, 0.92)",
    },
    {
      // Dark Amber
      base: "#1a1005",
      grad: "linear-gradient(160deg, #1a1005 0%, #28180a 30%, #381f0c 60%, #48260e 100%)",
      surface: "rgba(50, 28, 8, 0.92)",
      surfaceHover: "rgba(66, 38, 12, 0.94)",
      accent: "#fbbf24",
      accentGlow: "rgba(251, 191, 36, 0.45)",
      border: "rgba(251, 191, 36, 0.22)",
      toolbar: "rgba(30, 18, 5, 0.92)",
    },
    {
      // Slate Indigo
      base: "#0c0c1a",
      grad: "linear-gradient(160deg, #0c0c1a 0%, #121228 30%, #181838 60%, #1e1e48 100%)",
      surface: "rgba(22, 22, 55, 0.92)",
      surfaceHover: "rgba(30, 30, 72, 0.94)",
      accent: "#818cf8",
      accentGlow: "rgba(129, 140, 248, 0.45)",
      border: "rgba(129, 140, 248, 0.22)",
      toolbar: "rgba(14, 14, 36, 0.92)",
    },
  ],

  _currentIndex: 0,

  init() {
    gBrowser.tabContainer.addEventListener("TabSelect", this);
    // Sync chatbot button pressed state with sidebar open state
    const sidebarBox = document.getElementById("sidebar-box");
    if (sidebarBox) {
      sidebarBox.addEventListener("SidebarShown", this);
      sidebarBox.addEventListener("sidebar-hide", this);
    }
    // Apply the first palette on init to the current selected tab
    this._applyForTab(gBrowser.selectedTab);
  },

  uninit() {
    gBrowser.tabContainer.removeEventListener("TabSelect", this);
    const sidebarBox = document.getElementById("sidebar-box");
    if (sidebarBox) {
      sidebarBox.removeEventListener("SidebarShown", this);
      sidebarBox.removeEventListener("sidebar-hide", this);
    }
  },

  handleEvent(event) {
    if (event.type === "TabSelect") {
      this._applyForTab(event.target);
    } else if (event.type === "SidebarShown") {
      this._syncChatbotButton();
    } else if (event.type === "sidebar-hide") {
      this._syncChatbotButton();
    }
  },

  _syncChatbotButton() {
    const btn = document.getElementById("w3ai-chatbot-button");
    if (!btn) {
      return;
    }
    const isOpen =
      window.SidebarController?.isOpen &&
      window.SidebarController?.currentID === "viewGenaiChatSidebar";
    btn.setAttribute("aria-pressed", isOpen ? "true" : "false");
  },

  _applyForTab(tab) {
    const index = gBrowser.tabs.indexOf(tab);
    const paletteIndex = ((index >= 0 ? index : 0) % this.PALETTES.length);
    this._applyPalette(this.PALETTES[paletteIndex]);
    this._currentIndex = paletteIndex;
  },

  _applyPalette(palette) {
    const root = document.documentElement;
    root.style.setProperty("--w3ai-theme-bg-base", palette.base);
    root.style.setProperty("--w3ai-theme-bg-gradient", palette.grad);
    root.style.setProperty("--w3ai-theme-surface", palette.surface);
    root.style.setProperty("--w3ai-theme-surface-hover", palette.surfaceHover);
    root.style.setProperty("--w3ai-theme-accent", palette.accent);
    root.style.setProperty("--w3ai-theme-accent-glow", palette.accentGlow);
    root.style.setProperty("--w3ai-theme-border", palette.border);
    root.style.setProperty("--w3ai-theme-toolbar", palette.toolbar);
  },
};
