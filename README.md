# W3Ai Browser

**Built by [PlatoAi](https://platodata.io/) — The AI-First, Web3-Native Browser**

W3Ai Browser is a next-generation desktop browser built on Mozilla's open-source Gecko engine. It is not a reskin of Firefox — it is a purpose-built execution environment for AI agents, Web3 interactions, and privacy-first browsing, engineered for the decentralized web.

---

## What We Are Building

The web is changing. Static pages are giving way to agent-driven interactions, on-chain transactions, and AI-mediated experiences. Existing browsers were designed for the document web — not the agentic web.

W3Ai Browser is our answer:

- **Agentic Execution Layer** — AI agents run natively inside the browser, with sandboxed permissions, lifecycle management, and on-chain settlement
- **Built-in Web3** — Wallet connectivity, transaction simulation, and token-gated access without extensions
- **Embedded Exchange** — Native crypto swap powered by Changelly, built directly into the browser chrome
- **Privacy by Default** — No telemetry, no sync to third-party clouds, no tracking
- **PlatoAi Identity** — All branding, UX, and product decisions are driven by PlatoAi, not Mozilla

---

## Company

| | |
|---|---|
| **Company** | PlatoAi (Plato Technologies Inc.) |
| **Website** | https://platodata.io/ |
| **Browser** | W3Ai Browser |
| **Browser URL** | http://w3ai.io/ |

---

## Technical Foundation

W3Ai Browser is forked from Mozilla Firefox (Gecko engine, currently tracking Firefox 151). We use the full Gecko rendering engine, SpiderMonkey JS engine, and the Firefox extension ecosystem (MV2/MV3), while replacing:

- All Mozilla/Firefox branding with W3Ai/PlatoAi branding
- The default new tab page, home page, and about: pages
- The browser chrome UI (toolbar, sidebar, panels)
- The sync and accounts system (removed — we do not offer Mozilla Sync)
- The default search engine and suggestions

---

## Repository Structure

```
browser/
  branding/w3ai/          # W3Ai brand assets, icons, colors, FTL strings
  extensions/
    changelly-exchange/   # Built-in crypto swap extension (Changelly API)
  components/
    aiwindow/             # AI agent panel and window management
    sidebar/              # Custom W3Ai sidebar
toolkit/                  # Gecko toolkit (upstream Mozilla, minimally modified)
```

---

## Versioning

W3Ai Browser uses the versioning scheme `MAJOR.MINOR.PATCH`:

| Version | Base Firefox | Status |
|---------|-------------|--------|
| 1.0.0   | Firefox 151 | In development |

Version is tracked in [VERSION](./VERSION) and changes are logged in [CHANGELOG.md](./CHANGELOG.md).

---

## Building

W3Ai Browser uses Mozilla's `mach` build system. Full build documentation is available in [Firefox Source Docs](https://firefox-source-docs.mozilla.org/).

```bash
# Configure with W3Ai branding
./mach configure --with-branding=browser/branding/w3ai

# Build
./mach build

# Run
./mach run
```

---

## Roadmap

- [x] Custom branding (W3Ai icons, name, bundle ID)
- [x] Built-in Changelly exchange extension
- [ ] Centralized brand constants (eliminate hardcoded "Firefox"/"Mozilla" strings)
- [ ] Disable Firefox Sync UI
- [ ] Custom new tab page (W3Ai Home)
- [ ] AI agent panel (sidebar integration)
- [ ] Native wallet integration
- [ ] W3Ai token-gated features

---

## License

The W3Ai Browser source code is derived from Mozilla Firefox and is subject to the [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/). W3Ai-specific additions are copyright PlatoAi (Plato Technologies Inc.).
