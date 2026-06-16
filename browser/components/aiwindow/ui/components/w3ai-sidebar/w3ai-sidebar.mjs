/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// eslint-disable-next-line import/no-unassigned-import
import "chrome://browser/content/aiwindow/components/ai-window.mjs";

const { Services } = ChromeUtils.importESModule(
  "resource://gre/modules/Services.sys.mjs"
);

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  AgentPluginRegistry:
    "moz-src:///browser/components/aiwindow/services/AgentPluginRegistry.sys.mjs",
});

const YOUCOM_BASE = "https://api.ydc-index.io";

async function loadYoucomApiKey() {
  const envKey = Services.env.get("YOUCOM_API_KEY");
  if (envKey) {
    return envKey;
  }
  try {
    const envFile = PathUtils.join(PathUtils.profileDir, "w3ai.env");
    const content = await IOUtils.readUTF8(envFile);
    const match = content.match(/^YOUCOM_API_KEY=(.+)$/m);
    if (match?.[1]) {
      return match[1].trim();
    }
  } catch {
    // file not present
  }
  return "";
}

const TABS = ["chat", "summary", "search", "content", "research", "finance"];

const TAB_CONFIG = {
  search: { label: "WEB SEARCH", desc: "Live web results from across the open web.", endpoint: "search" },
  content: { label: "CONTENT", desc: "Curated content results.", endpoint: "search" },
  research: { label: "RESEARCH", desc: "Deep research and analysis.", endpoint: "rag" },
  finance: { label: "FINANCE", desc: "Financial news and market data.", endpoint: "news" },
};

class W3AiSidebar extends HTMLElement {
  #shadow;
  #activeTab = "chat";
  #currentUrl = "";
  #currentHost = "";
  #agentName = "TMRW Agent";
  #agentLabel = "TMRW · SIDEBAR";
  #plugin = null;
  #youcomKey = "";
  #searchQueries = {};
  #searchResults = {};
  #searchLoading = {};

  constructor() {
    super();
    this.#shadow = this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.#render();
    this.#attachListeners();
    loadYoucomApiKey().then(key => {
      this.#youcomKey = key;
    });
    this.#syncPageContext();

    window.addEventListener("ai-window:sidebar-toggle", this.#onSidebarToggle);
    window.browsingContext?.topChromeWindow?.addEventListener(
      "TabSelect",
      this.#onTabSelect
    );
  }

  disconnectedCallback() {
    window.removeEventListener("ai-window:sidebar-toggle", this.#onSidebarToggle);
    window.browsingContext?.topChromeWindow?.removeEventListener(
      "TabSelect",
      this.#onTabSelect
    );
  }

  #onSidebarToggle = () => this.#syncPageContext();
  #onTabSelect = () => this.#syncPageContext();

  #syncPageContext() {
    const chromeWin = window.browsingContext?.topChromeWindow;
    if (!chromeWin) {
      return;
    }
    const uri = chromeWin.gBrowser?.selectedBrowser?.currentURI;
    this.#currentUrl = uri?.spec ?? "";
    this.#currentHost = uri?.host ?? "";
    this.#plugin = lazy.AgentPluginRegistry.getPluginForUrl(this.#currentUrl);
    this.#agentName = this.#plugin?.name ?? "TMRW Agent";

    const hostEl = this.#shadow.getElementById("current-url");
    if (hostEl) {
      hostEl.textContent = this.#currentHost || "—";
    }
    const agentEl = this.#shadow.getElementById("agent-name");
    if (agentEl) {
      agentEl.textContent = this.#agentName;
    }
    const statusEl = this.#shadow.getElementById("context-line");
    if (statusEl) {
      const watchLabel = this.#plugin?.label ?? this.#currentHost ?? "Page";
      statusEl.textContent = `Watching ${watchLabel} · Live · UTC`;
    }
    this.#updateDetectedActions();
    this.#applyThemeVars();
  }

  #applyThemeVars() {
    const root = this.#shadow.host;
    const theme = this.#plugin?.theme;
    if (theme) {
      root.style.setProperty("--sidebar-bg", theme.background ?? "");
      root.style.setProperty("--sidebar-accent", theme.accent ?? "");
      root.style.setProperty("--sidebar-primary", theme.primary ?? "");
    } else {
      const style = getComputedStyle(document.documentElement);
      root.style.setProperty("--sidebar-bg", style.getPropertyValue("--agent-bg") || "");
      root.style.setProperty("--sidebar-accent", style.getPropertyValue("--agent-accent") || "");
      root.style.setProperty("--sidebar-primary", style.getPropertyValue("--agent-primary") || "");
    }
  }

  #updateDetectedActions() {
    const container = this.#shadow.getElementById("detected-actions");
    if (!container) {
      return;
    }
    const prompts = this.#plugin?.suggestedPrompts ?? [];
    if (!prompts.length) {
      container.closest("#detected-section").hidden = true;
      return;
    }
    container.closest("#detected-section").hidden = false;
    container.innerHTML = "";
    prompts.slice(0, 4).forEach(prompt => {
      const item = document.createElement("button");
      item.className = "detected-item";
      item.textContent = prompt;
      item.addEventListener("click", () => this.#injectPromptToChat(prompt));
      container.appendChild(item);
    });
  }

  #injectPromptToChat(prompt) {
    this.#switchTab("chat");
    const aiWindow = this.#shadow.querySelector("ai-window");
    if (aiWindow?.updateInput) {
      aiWindow.updateInput(prompt);
    }
  }

  #attachListeners() {
    this.#shadow.addEventListener("click", e => {
      const tab = e.target.closest("[data-tab]");
      if (tab) {
        this.#switchTab(tab.dataset.tab);
        return;
      }
      if (e.target.id === "btn-collapse") {
        const chromeWin = window.browsingContext?.topChromeWindow;
        chromeWin?.AIWindowUI?.toggleSidebar(chromeWin);
        return;
      }
      const runBtn = e.target.closest(".search-run-btn");
      if (runBtn) {
        const panel = runBtn.closest(".you-panel");
        const type = panel?.dataset.type;
        const input = panel?.querySelector(".search-input");
        if (type && input?.value.trim()) {
          this.#runSearch(type, input.value.trim());
        }
        return;
      }
      const resultLink = e.target.closest(".result-title-link");
      if (resultLink) {
        e.preventDefault();
        this.#openInMainTab(resultLink.dataset.url);
        return;
      }
    });

    this.#shadow.addEventListener("keydown", e => {
      if (e.key === "Enter" && e.target.classList.contains("search-input")) {
        const panel = e.target.closest(".you-panel");
        const type = panel?.dataset.type;
        if (type && e.target.value.trim()) {
          this.#runSearch(type, e.target.value.trim());
        }
      }
    });
  }

  #switchTab(tabName) {
    if (!TABS.includes(tabName)) {
      return;
    }
    this.#activeTab = tabName;

    this.#shadow.querySelectorAll("[data-tab]").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.tab === tabName);
      btn.setAttribute("aria-selected", btn.dataset.tab === tabName);
    });
    this.#shadow.querySelectorAll(".panel").forEach(panel => {
      panel.hidden = panel.id !== `panel-${tabName}`;
    });
  }

  async #runSearch(type, query) {
    this.#searchLoading[type] = true;
    this.#searchQueries[type] = query;
    this.#renderSearchResults(type, null, true);

    const key = this.#youcomKey;
    if (!key) {
      this.#searchResults[type] = { error: "no_key" };
      this.#searchLoading[type] = false;
      this.#renderSearchResults(type, { error: "no_key" }, false);
      return;
    }

    const cfg = TAB_CONFIG[type];
    let url;
    let opts = { headers: { "X-API-Key": key } };

    if (cfg.endpoint === "search") {
      url = `${YOUCOM_BASE}/search?query=${encodeURIComponent(query)}&num_web_results=10`;
    } else if (cfg.endpoint === "rag") {
      url = `${YOUCOM_BASE}/rag?query=${encodeURIComponent(query)}&num_web_results=8`;
    } else if (cfg.endpoint === "news") {
      url = `${YOUCOM_BASE}/news?q=${encodeURIComponent(query)}`;
    }

    try {
      const resp = await fetch(url, opts);
      const json = await resp.json();
      this.#searchResults[type] = json;
      this.#renderSearchResults(type, json, false);
    } catch (err) {
      this.#searchResults[type] = { error: err.message };
      this.#renderSearchResults(type, { error: err.message }, false);
    }
    this.#searchLoading[type] = false;
  }

  #renderSearchResults(type, data, loading) {
    const panel = this.#shadow.getElementById(`panel-${type}`);
    if (!panel) {
      return;
    }
    const resultsEl = panel.querySelector(".results-area");
    if (!resultsEl) {
      return;
    }

    if (loading) {
      resultsEl.innerHTML = `<div class="loading-msg">Fetching results…</div>`;
      return;
    }

    if (!data) {
      resultsEl.innerHTML = "";
      return;
    }

    if (data.error) {
      const msg = data.error === "no_key"
        ? `<div class="error-msg">You.com API key not configured.<br>Set <code>YOUCOM_API_KEY</code> in the environment or <code>w3ai.env</code> in your profile.</div>`
        : `<div class="error-msg">Error: ${data.error}</div>`;
      resultsEl.innerHTML = msg;
      return;
    }

    // Normalize hits from different endpoint shapes
    let hits = data.hits ?? data.news?.results ?? [];
    if (type === "research" && data.answer) {
      resultsEl.innerHTML = `<div class="rag-answer">${this.#esc(data.answer)}</div>`;
      if (hits.length) {
        resultsEl.innerHTML += `<div class="results-label">SOURCES</div>` + this.#buildHitsList(hits);
      }
      return;
    }

    const ts = new Date().toLocaleString("en-US", { month: "short", day: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
    resultsEl.innerHTML = `<div class="fetch-ts">LATEST · FETCHED ${ts.toUpperCase()}</div>` + this.#buildHitsList(hits);
  }

  #buildHitsList(hits) {
    if (!hits.length) {
      return `<div class="no-results">No results found.</div>`;
    }
    return hits.map(hit => {
      const url = hit.url ?? hit.link ?? "";
      const title = this.#esc(hit.title ?? "Untitled");
      const desc = this.#esc(hit.description ?? hit.snippet ?? "");
      const date = hit.published_date ? `<div class="result-date">${this.#esc(hit.published_date)}</div>` : "";
      const host = url ? new URL(url).hostname : "";
      return `
        <div class="result-card">
          <button class="result-title-link" data-url="${this.#esc(url)}">${title}</button>
          <div class="result-host">${this.#esc(host)}</div>
          ${desc ? `<div class="result-desc">${desc}</div>` : ""}
          ${date}
        </div>`;
    }).join("");
  }

  #esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  #openInMainTab(url) {
    if (!url) {
      return;
    }
    try {
      const chromeWin = window.browsingContext?.topChromeWindow;
      chromeWin?.openTrustedLinkIn(url, "current");
    } catch {
      // fallback: navigate current tab
    }
  }

  #buildSummaryPanel() {
    return `
      <div class="panel" id="panel-summary">
        <div class="panel-inner">
          <div class="section-label">PAGE SUMMARY</div>
          <div class="summary-desc">AI-generated summary of the current page.</div>
          <button class="summarize-btn" id="summarize-btn">Summarize this page</button>
          <div id="summary-result" class="summary-result"></div>
        </div>
      </div>`;
  }

  #buildYouPanel(type) {
    const cfg = TAB_CONFIG[type];
    return `
      <div class="panel you-panel" id="panel-${type}" data-type="${type}" hidden>
        <div class="panel-inner">
          <div class="section-label">${cfg.label}</div>
          <div class="search-desc">${cfg.desc}</div>
          <div class="search-row">
            <input class="search-input" type="text" placeholder="Ask anything…"
              value="${this.#esc(this.#searchQueries[type] ?? "")}" />
            <button class="search-run-btn">Run ➤</button>
          </div>
          <div class="results-area"></div>
        </div>
      </div>`;
  }

  #render() {
    const tabsHtml = TABS.map(t => `
      <button role="tab" aria-selected="${t === "chat"}" class="tab${t === "chat" ? " active" : ""}" data-tab="${t}">
        ${t.charAt(0).toUpperCase() + t.slice(1)}
      </button>`).join("");

    this.#shadow.innerHTML = `
      <link rel="stylesheet" href="chrome://browser/content/aiwindow/components/w3ai-sidebar.css" />
      <div id="shell">
        <header id="w3ai-header">
          <div class="identity">
            <div class="avatar">
              <svg width="20" height="20" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <g fill="white">
                  <ellipse cx="8" cy="8" rx="1.7" ry="3.6" transform="rotate(0 8 8)"/>
                  <ellipse cx="8" cy="8" rx="1.7" ry="3.6" transform="rotate(45 8 8)"/>
                  <ellipse cx="8" cy="8" rx="1.7" ry="3.6" transform="rotate(90 8 8)"/>
                  <ellipse cx="8" cy="8" rx="1.7" ry="3.6" transform="rotate(135 8 8)"/>
                </g>
                <circle cx="8" cy="8" r="1.3" fill="white"/>
              </svg>
            </div>
            <div class="brand">
              <span class="brand-label">${this.#agentLabel}</span>
              <span class="brand-title" id="agent-name">${this.#agentName}</span>
            </div>
          </div>
          <div class="header-actions">
            <button class="icon-btn" id="btn-pin" title="Pin sidebar" aria-label="Pin sidebar">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M10 2L14 6L9.5 7.5L8 12L4 8L5.5 6.5L7 5L10 2Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/>
                <line x1="2" y1="14" x2="5" y2="11" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
              </svg>
            </button>
            <button class="icon-btn" id="btn-more" title="More options" aria-label="More options">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <circle cx="4" cy="8" r="1.2" fill="currentColor"/>
                <circle cx="8" cy="8" r="1.2" fill="currentColor"/>
                <circle cx="12" cy="8" r="1.2" fill="currentColor"/>
              </svg>
            </button>
            <button class="icon-btn" id="btn-collapse" title="Close sidebar" aria-label="Close sidebar">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <rect x="1.5" y="1.5" width="13" height="13" rx="2" stroke="currentColor" stroke-width="1.4"/>
                <line x1="10" y1="1.5" x2="10" y2="14.5" stroke="currentColor" stroke-width="1.4"/>
                <path d="M12 6L14 8L12 10" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </div>
        </header>

        <div id="url-bar">
          <svg class="globe-icon" width="14" height="14" viewBox="0 0 16 16" fill="none">
            <circle cx="8" cy="8" r="6.5" stroke="currentColor" stroke-width="1.3"/>
            <ellipse cx="8" cy="8" rx="3" ry="6.5" stroke="currentColor" stroke-width="1.3"/>
            <line x1="1.5" y1="8" x2="14.5" y2="8" stroke="currentColor" stroke-width="1.3"/>
          </svg>
          <span id="current-url" class="url-text">${this.#currentHost || "—"}</span>
          <span class="live-badge"><span class="live-dot"></span> LIVE</span>
        </div>

        <nav id="tab-strip" role="tablist" aria-label="Sidebar tabs">
          ${tabsHtml}
        </nav>

        <div id="context-line">Watching · Live · UTC</div>

        <div id="panels">
          <div class="panel" id="panel-chat">
            <ai-window mode="sidebar" no-header></ai-window>
          </div>
          ${this.#buildSummaryPanel()}
          ${this.#buildYouPanel("search")}
          ${this.#buildYouPanel("content")}
          ${this.#buildYouPanel("research")}
          ${this.#buildYouPanel("finance")}
        </div>

        <div id="detected-section">
          <div class="detected-label">DETECTED ON PAGE</div>
          <div id="detected-actions"></div>
        </div>

        <footer id="w3ai-footer">
          <span class="footer-left">⬡ ENCLAVE · <span id="tracker-count">0</span> TRACKERS</span>
          <kbd class="footer-kbd">⌥\\ TO TOGGLE</kbd>
        </footer>
      </div>`;

    this.#attachSummaryListener();
    this.#switchTab(this.#activeTab);
    this.#syncPageContext();
  }

  #attachSummaryListener() {
    const btn = this.#shadow.getElementById("summarize-btn");
    if (!btn) {
      return;
    }
    btn.addEventListener("click", async () => {
      const resultEl = this.#shadow.getElementById("summary-result");
      resultEl.textContent = "Summarizing…";
      btn.disabled = true;

      const key = this.#youcomKey;
      if (!key) {
        resultEl.innerHTML = `<div class="error-msg">You.com API key not configured.<br>Set <code>YOUCOM_API_KEY</code> in the environment or <code>w3ai.env</code> in your profile.</div>`;
        btn.disabled = false;
        return;
      }

      const pageTitle = window.browsingContext?.topChromeWindow?.gBrowser?.selectedBrowser?.contentTitle ?? "";
      const query = `Summarize this page: ${pageTitle || this.#currentUrl}`;
      const url = `${YOUCOM_BASE}/rag?query=${encodeURIComponent(query)}&num_web_results=3`;

      try {
        const resp = await fetch(url, { headers: { "X-API-Key": key } });
        const json = await resp.json();
        resultEl.innerHTML = json.answer
          ? `<div class="rag-answer">${this.#esc(json.answer)}</div>`
          : `<div class="no-results">No summary available.</div>`;
      } catch (err) {
        resultEl.innerHTML = `<div class="error-msg">Error: ${this.#esc(err.message)}</div>`;
      }
      btn.disabled = false;
    });
  }
}

customElements.define("w3ai-sidebar", W3AiSidebar);
