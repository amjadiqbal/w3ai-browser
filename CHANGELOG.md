# Changelog

All notable changes to W3Ai Browser are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
W3Ai versioning: `MAJOR.MINOR.PATCH` (independent of upstream Firefox version).

---

## [Unreleased]

### Added
- **Milestone 16** — PageAssist real Claude API integration (`browser/components/genai/PageAssist.sys.mjs`)
  - Replaced mock stub with live Anthropic API (`claude-opus-4-8`)
  - SSE stream parsing with `cache_control: {type: "ephemeral"}` on page context for prompt caching
  - Reads API key from `browser.smartwindow.apiKey` pref; graceful error messages when unconfigured
- Root `README.md` rewritten with W3Ai/PlatoAi branding and product vision
- `VERSION` file introduced for explicit W3Ai version tracking
- `CHANGELOG.md` introduced
- Changelly exchange backend: secure environment setup script (`scripts/setup-env.sh`)
- Changelly exchange: fiat API endpoints (`FIAT_API_ENDPOINTS.md`, `src/routes/fiat.ts`, `src/clients/changelly-fiat.ts`)
- Changelly exchange: fiat popup screen (`src/popup/screens/FiatScreen.tsx`)
- Changelly exchange: extension icons set (16, 19, 32, 38, 48, 96, 128px + SVG)
- Changelly exchange: additional tests (`AppBoot.test.tsx`, `FiatPopupFlow.test.tsx`, `PopupSizing.test.tsx`)

### Changed
- Changelly exchange backend: hardened env configuration (`src/env.ts`)
- Changelly exchange: updated manifest, popup HTML, App.tsx, AppStore, styles
- AI Window component updates (`browser/components/aiwindow/`)
- CustomizableUI updates for W3Ai toolbar layout
- Extension system: `ExtensionActions.sys.mjs`, `aboutaddons.js`, `XPIDatabase.sys.mjs` modified for built-in extension handling

---

## [1.0.0] - In Development (base: Firefox 151)

### Added
- W3Ai branding: `browser/branding/w3ai/` — icons, configure.sh, brand.ftl, brand.properties
  - `MOZ_APP_DISPLAYNAME = "W3Ai Browser"`, `MOZ_APP_REMOTINGNAME = w3ai`, `MOZ_MACBUNDLE_ID = org.w3ai.browser`
  - Vendor: Plato, Full name: Plato W3Ai Browser
- Built-in Changelly exchange extension: `browser/extensions/changelly-exchange/`
  - Proxy backend (TypeScript/Express), popup UI (React/TypeScript), MV2 manifest
- Custom AI agent window panel: `browser/components/aiwindow/`
- Custom sidebar with W3Ai layout and animations
- macOS notarization and release build scripts
- Android emulator and iOS simulator CI workflows
- GitHub Copilot instructions for branching, release, and deployment

### Changed
- Browser chrome customizations via `CustomizableUI.sys.mjs`
- Sidebar content ordering and transition animations

---

*Upstream Firefox version: 151.0a1*
*W3Ai Browser version managed in [VERSION](./VERSION)*
