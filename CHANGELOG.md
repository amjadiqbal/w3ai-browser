# Changelog

All notable changes to W3Ai Browser are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
W3Ai versioning: `MAJOR.MINOR.PATCH` (independent of upstream Firefox version).

---

## [Unreleased]

### Added
- **Milestone 17** — Custom default top sites + disable trending URL-bar suggestions
  - `firefox.js`: `browser.newtabpage.activity-stream.default.sites` set to W3Ai properties (tmrw.w3ai.io, tmrw-digital.com, c100.w3ai.io, coinmarketcap.com)
  - `firefox.js`: `browser.urlbar.trending.featureGate` and `browser.urlbar.suggest.trending` disabled — removes "Trending on Google" from empty URL bar
- **Milestone 16** — W3Ai brand accent color (logo blue `#00A4FD` replaces Firefox cyan `#00DDFF`)
  - `browser-colors.css`: `--color-accent-primary`, `--focus-outline-color`, `--link-color` (and hover/active variants) → `#0067CC` (light) / `#00A4FD` (dark)
  - `browser-shared.css`: swipe-nav icon primary color updated
  - `formautofill-notification.css`: diff highlight color updated
  - `panelUI-shared.css`: radio-check selected border updated
  - `aboutPrivateBrowsing.css`: CTA button background updated
  - `organizer.css`: bookmarks organizer focus-selected color updated
  - `pictureinpicture/player.css`: radio border + toggle slider updated
  - `videocontrols.css`: control focus outline updated
  - `aboutReader.css`: reader mode selected highlight and primary color updated
- **Milestone 13** — Zero out remaining Mozilla FxA server URLs
  - `firefox-branding.js`: explicit empty-string overrides for `identity.fxaccounts.remote.root`, `.profile.uri`, `.oauth.uri` — ensures no Mozilla account server is contacted even if `identity.fxaccounts.enabled` changes
- **Milestone 8** — Privacy / telemetry hardening
  - `firefox-branding.js`: disable Glean/healthreport upload, all classic telemetry pings, DAP measurement tasks, Normandy remote recipe execution, Shield studies, crash report auto-submission; zero out Merino, contile, partner attribution, coverage, MITM priming, IPProtection, FxA association ping, and SERP event telemetry endpoints
- **Milestone 4** — Disable Firefox updater UI
  - `distribution/policies.json` (new): `DisableAppUpdate: true` — enterprise policy engine blocks all update activity with no Mozilla server contact
  - `distribution/moz.build`: ship `policies.json` to `dist/bin/distribution/` in all builds
  - `aboutDialog.ftl`: `update-policy-disabled` → `{ -brand-short-name } is up to date` (clean, brand-appropriate)
  - `preferences.ftl`: `managed-notice` → `{ -brand-short-name } settings are managed by { -vendor-short-name }.`
- **Milestone 15** — About:Addons branding cleanup
  - `aboutAddons.ftl`: replace AMO search placeholders with "Search for extensions"; remove "built by Mozilla" from official badge tooltip; replace "Firefox Color" theme recommendation with W3Ai-branded copy
  - `firefox-branding.js`: disable remote discovery recommendations panel (API server not live); clean up extension URL overrides
- **Milestone 12** — Preferences UI cleanup
  - `preferences.js`: remove Nimbus-controlled "More from Mozilla" panel trigger
  - `aiFeatures.mjs`, `privacy.inc.xhtml`: replace firefox-prefixed support-page keys with w3ai-prefixed equivalents
- **Milestone 11** — firefox-help topic key → w3ai-help
  - `aboutDialog.js`, `browser.js`: replace `openHelpLink("firefox-help")` with `openHelpLink("w3ai-help")`
- **Milestone 10** — W3Ai Home new tab branding
  - `newtab.ftl`: rename tab title from "New Tab" to "W3Ai Home"; update wallpaper section comment
  - `WallpaperFeed.sys.mjs`: filter out Firefox-branded wallpapers (category "firefox") from the picker
- **Milestone 9** — about:support Name field and branding strings
  - `moz.configure`: `MOZ_APP_VENDOR = Plato`; `--with-app-basename = W3Ai`; `--with-app-name = firefox`
  - `configure.sh`: `MOZ_CRASHREPORTER_URL = https://crash-reports.plato.ai`
- **Milestone 3** — About W3Ai dialog branding
  - `aboutDialog.xhtml`: replace all Mozilla/foundation links with plato.ai/w3ai.io URLs; Terms and Privacy point to plato.ai
  - `aboutDialog.ftl`: replace "global community" with "AI-first technology company"; update helpus CTA
- **Milestone 2** — Toolkit brand string audit
  - `brandings.ftl`: Screenshots, Profiler, Translations, Suggest, Home, View, Labs now use `{ -brand-short-name }` token
  - `aboutAddons.ftl`: recommendations, badge tooltip, block notices, OpenH264 use brand tokens
- **Milestone 1** — W3Ai custom new tab page
  - `firefox.js`: disable Pocket/Discovery Stream, sponsored stories/topsites, newtab telemetry pings; always show wordmark; hide promo card
  - `firefox-wordmark.svg`: use `context-fill` so CSS controls the wordmark colour (light/dark aware)
  - `newtab.ftl`: section header comment updated to "W3Ai Home"
- `browser/branding/w3ai/`: W3Ai branding assets transplanted onto clean Firefox base
- `VERSION`: introduced for explicit W3Ai version tracking

---

## [1.0.0] - In Development (base: Firefox 151)

### Added
- W3Ai branding: `browser/branding/w3ai/` — icons, configure.sh, brand.ftl, brand.properties
  - `MOZ_APP_DISPLAYNAME = "W3Ai Browser"`, `MOZ_APP_REMOTINGNAME = w3ai`, `MOZ_MACBUNDLE_ID = org.w3ai.browser`
  - Vendor: Plato, Full name: Plato W3Ai Browser

---

*Upstream Firefox version: 151.0a1*
*W3Ai Browser version managed in [VERSION](./VERSION)*
