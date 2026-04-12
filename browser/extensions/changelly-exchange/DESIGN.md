# Changelly Exchange Extension — Production Design Document

## 1. Executive Architecture Summary

The Changelly Exchange extension ships as a **built-in system add-on** in the W3Ai custom Firefox
distribution. It provides a premium, wallet-first crypto exchange experience powered by the
Changelly Exchange API v2 and Changelly DeFi Swap APIs. All privileged Changelly API calls
(authentication, signing, transaction creation) are routed through a companion backend proxy
service; the extension itself never holds long-lived private secrets.

**System layers:**

```
┌─────────────────────────────────────────────────────────────┐
│  Custom Firefox (W3Ai)                                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  changelly-exchange system add-on                     │  │
│  │  ├─ popup/     React UI (dark-mode, swap widget)      │  │
│  │  ├─ background/ Service worker (state, messaging)     │  │
│  │  ├─ content/   Page-level wallet bridge               │  │
│  │  └─ shared/    Types, validation, formatting          │  │
│  └─────────────────────┬─────────────────────────────────┘  │
└────────────────────────┼────────────────────────────────────┘
                         │ HTTPS (fetch, CSP-controlled)
         ┌───────────────▼───────────────────┐
         │  Backend Proxy Service             │
         │  (TypeScript + Fastify + Zod)      │
         │  ├─ /config/public                 │
         │  ├─ /assets  /pairs  /quote        │
         │  ├─ /swap/create  /swap/:id        │
         │  └─ /defi/intent  /defi/approval   │
         └───────────────┬───────────────────┘
                         │ Signed HTTPS
         ┌───────────────▼───────────────────┐
         │  Changelly APIs                   │
         │  ├─ Exchange API v2               │
         │  └─ DeFi Swap API                 │
         └───────────────────────────────────┘
```

---

## 2. Firefox Packaging Strategy

### Approach Comparison

| Criterion              | A: Enterprise Policy | B: distribution/extensions | C: System Add-on (built-in) |
|------------------------|----------------------|----------------------------|-----------------------------|
| Default installed      | Yes (via policies.json) | Yes | Yes |
| User can disable       | Configurable         | Yes                        | Yes |
| User cannot remove     | Yes (locked)         | No — user can remove       | Yes — no remove button |
| Updates via AMO        | Yes                  | No                         | Browser update channel |
| Custom build required  | No                   | No                         | Yes |
| Source-code control    | Partial              | No                         | Full |
| Signing flexibility    | AMO or enterprise    | AMO required               | Exempt (built-in) |

### Recommended: Approach C — Built-in System Add-on

**Justification:**
- System add-ons (shipped in `browser/extensions/`) render **without** an uninstall button. The
  user sees only an enable/disable toggle in `about:addons`.
- We own the Firefox build, so MOZ_DISTRIBUTION signing exemptions apply.
- Updates are delivered via the browser update channel, not AMO, giving us full control.
- No runtime policy configuration infrastructure is needed.

**Implementation rules:**
1. Extension lives at `browser/extensions/changelly-exchange/`.
2. Added to `browser/extensions/moz.build` DIRS list.
3. `jar.mn` manifest packages source files into the distribution.
4. `manifest.json` uses `browser_specific_settings.gecko.id: "changelly-exchange@w3ai.io"`.
5. To block removal at UI level, set `locked: true` in `browser/components/extensions/`:
   a pre-installed extension with the `locked` attribute cannot be removed via the UI.
   In practice, for built-in extensions shipped in the browser directory this is automatic —
   `about:addons` shows the extension as built-in and the "Remove" button is absent.

**Extension ID:** `changelly-exchange@w3ai.io` (fixed, never changes between builds)

**QA vs Production builds:**
- `CHANGELLY_ENV=staging` / `CHANGELLY_ENV=production` injected at build time via
  `browser/extensions/changelly-exchange/src/config/env.ts` (generated, not committed).
- This file contains only public non-sensitive values: proxy base URL, feature flag URL,
  supported environments list. Zero secrets.

**Update delivery:**
- Extension version is pinned to the browser version in `manifest.json`.
- Updated via browser OTA update channel (`update_manifests/`).
- Hotfix-only extension updates via a separate extension update URL pointing at our
  controlled update server (XPI hosted at `https://updates.w3ai.io/extensions/`).

---

## 3. Changelly API Mapping

### A. Exchange API v2 Modules

| Functional Area | Endpoint / Method | App Module | Journey Phase | Proxy Required |
|---|---|---|---|---|
| Authentication | HMAC-SHA512 signature on every request | `backend/security/changelly-signer` | All | **Yes** — private key server-only |
| Currencies list | `getCurrencies` | `services/asset-service` | App init, token picker | Yes |
| Currency metadata | `getCurrencyFull` | `services/asset-service` | Token detail panel | Yes |
| Available pairs | `getPairsParams` | `services/pair-service` | Quote init, token selection | Yes |
| Floating estimate | `getExchangeAmount` | `services/quote-service` | Quote display | Yes |
| Floating creation | `createTransaction` | `services/swap-service` | Swap execution | Yes |
| Fixed-rate estimate | `getFixAmount` | `services/quote-service` | Fixed-rate quote | Yes |
| Fixed creation | `createFixTransaction` | `services/swap-service` | Fixed-rate execution | Yes |
| Transaction lookup | `getTransactions` | `services/history-service` | History, recovery | Yes |
| Transaction status | `getStatus` | `services/status-service` | Live tracking | Yes |
| Address validation | `validateAddress` | `services/validation-service` | Recipient entry | Yes |
| DEPRECATED (skip) | `exchangeAmount` (v1) | — | — | — |

**Authentication model:** Changelly Exchange API v2 uses JSON-RPC 2.0 over HTTPS with each
request signed by `HMAC-SHA512(body, privateKey)` and the `api-key` header set. The private key
**must never leave the backend**. The backend proxy signs every outbound Changelly request.

### B. DeFi Swap API Modules

| Functional Area | Endpoint | App Module | Wallet Interaction | Risk Points |
|---|---|---|---|---|
| Auth/signing | API key + HMAC signature | `backend/security/defi-signer` | None | Key must be server-only |
| Supported networks | `GET /v1/networks` | `services/network-service` | None | Cache 10 min |
| Supported tokens | `GET /v1/tokens?network=` | `services/asset-service` | None | Large payload, paginate |
| Token search | `GET /v1/tokens?search=` | `services/asset-service` | None | Debounce 300 ms |
| Intent creation | `POST /v1/intent` | `services/defi-service` | Wallet address | Irreversible |
| Quote/route | `GET /v1/quote` | `services/quote-service` | None | 30 s TTL |
| EVM approval | `POST /v1/approval` | `services/approval-service` | EIP-712 / eth_sendTransaction | User may reject |
| Status tracking | `GET /v1/intent/:id/status` | `services/status-service` | None | Poll 5 s |
| Same-chain swap | intent with same fromNetwork / toNetwork | `services/defi-service` | Single tx | Gas estimation |
| Cross-chain swap | intent with different networks | `services/defi-service` | Source chain tx | Bridge delays |
| Custom tokens | token not in /v1/tokens list | `services/asset-service` | User provides contract | Scam risk - warn |
| Wrapped tokens | WETH/WMATIC auto-handling | `services/defi-service` | Transparent | Verify with account team |

**Classic Exchange vs DeFi decision tree:**
- User provides a destination address (custodial/CEX): → classic Exchange API
- User connects an EVM/wallet and wants on-chain swap: → DeFi Swap API
- Feature flag `DEFI_ENABLED=true` gates DeFi path; defaults to classic for all non-EVM assets

---

## 4. User Journeys

### Journey 1: First Launch
- **Trigger:** User opens browser for the first time after installation.
- **Steps:**
  1. Extension background starts → fetches `/config/public` from proxy.
  2. First-run flag not set → popup opens to onboarding screen.
  3. User reads brief exchange education (3 cards, skip allowed).
  4. User accepts Terms & Privacy notice.
  5. Onboarding completes → first-run flag set in `browser.storage.local`.
  6. Swap home screen shown.
- **Error state:** Proxy unreachable → onboarding completes but shows degraded-mode banner.

### Journey 2: Simple Floating-Rate Swap
- **Trigger:** User clicks extension icon.
- **Steps:**
  1. Swap home shown with last-used asset pair (or BTC→ETH default).
  2. User selects source asset → token picker opens → user selects BTC.
  3. User enters amount → quote debounced 600 ms → `POST /quote/floating`.
  4. Rate, fee, estimated output rendered.
  5. User enters recipient ETH address.
  6. `POST /validate/address` confirms address is valid.
  7. Review screen shown (rate summary, fees, recipient).
  8. User taps "Confirm Swap".
  9. `POST /swap/create` → returns `id`, `payinAddress`, `expectedAmount`.
  10. Extension shows pending screen with deposit address QR / copy.
  11. Background polls `GET /swap/:id/status` every 10 s.
  12. Status transitions: `waiting → confirming → exchanging → finished`.
  13. Success screen with receipt.
- **Analytics:** `swap_initiated`, `swap_confirmed`, `swap_completed`.

### Journey 3: Fixed-Rate Swap
- Same as Journey 2 but user toggles "Fixed Rate" mode.
- `POST /quote/fixed` used; rate is guaranteed for 15 min (TTL shown as countdown).
- On TTL expiry: banner "Rate expired — refresh?" → user approves → `POST /quote/fixed` again.
- `POST /swap/create` with `rateId` included.

### Journey 4: DeFi Same-Chain Swap (feature-flagged)
- **Precondition:** `DEFI_ENABLED=true`, user has connected EVM wallet.
- Steps: select from/to tokens (same chain) → quote route shown → user approves token spend
  (EIP-712 or `eth_sendTransaction`) → swap tx submitted → status tracked.

### Journey 5: DeFi Cross-Chain Swap
- Same as Journey 4 but from/to are different chains.
- Additional step: bridge route shown with estimated bridge time.
- Warning banner: "Cross-chain swaps may take 5–30 minutes."

### Journey 6: Recipient Address Validation Failure
- User types address → `POST /validate/address` returns `result: false`.
- Error shown inline: "Invalid address for this network."
- CTA disabled until corrected.

### Journey 7: Quote Expires / Refreshes
- 30 s quote TTL shown as radial countdown.
- On expiry: quote dims with "Expired" badge, "Refresh" button appears.
- Auto-refresh every 30 s when user is on review screen.

### Journey 8: Approval Rejected
- DeFi path only: wallet popup appears → user rejects.
- Extension shows: "Transaction rejected — your wallet cancelled the approval."
- CTA returns to review screen; no swap was created.

### Journey 9: Transaction Hold / KYC
- `status = "hold"` received from `/swap/:id/status`.
- Extension shows hold screen: "Your exchange is on hold — Changelly may contact you."
- Support link to Changelly support URL shown.
- Analytics: `swap_held`.

### Journey 10: Partial Failure / Recovery After Restart
- In-progress swap state persisted to `browser.storage.local` (`currentSwap`).
- On next popup open: background checks persisted swap → fetches live status → resumes tracking.
- If state is terminal (`finished`/`failed`/`refunded`) → auto-clear draft, show receipt.

### Journey 11: Extension Disabled Then Re-enabled
- State in `browser.storage.local` survives disable/enable cycle.
- On re-enable: background re-fetches config, resumes in-flight swap polling if any.
- History intact.

### Journey 12: Network Congestion / Retry / Stale Quote
- `POST /swap/create` returns 503 → exponential backoff, max 3 retries.
- After 3 retries: "Service temporarily unavailable, try again later."
- Quote refreshed automatically before retry attempt.

### Journey 13: Unsupported Asset/Network
- Token picker filters out pairs where `available: false`.
- If user somehow selects an unavailable pair: inline warning, CTA disabled.

### Journey 14: Custom Token Flow
- DeFi path only; user pastes a contract address not in token list.
- Warning: "This is an unverified token. Proceed with caution."
- Confirmation checkbox required before custom token is used.

---

## 5. Feature Specification

See "Core Modules" and "Optional Modules" in the extension source README. All capabilities listed
in Section 4 (Product Strategy) of the prompt are implemented. Feature flags control DeFi path,
custom tokens, testnet mode, and referral surfaces.

---

## 6. Security Architecture

### Threat Model
- **Attacker capabilities:** Can read all packaged JS, intercept unencrypted network requests,
  read extension storage, inject content scripts into pages, forge requests to the proxy.
- **Assets at risk:** Changelly private key (signs all Changelly requests), user swap history,
  user wallet addresses.

### Trust Boundaries
```
[Extension code]  — public, inspectable
[Browser storage] — user-device-local, not server-accessible
[Backend proxy]   — trusted server, holds secrets
[Changelly APIs]  — third-party, authenticated by proxy
[User wallet]     — user-controlled, no custody here
```

### Non-Negotiable Rules
1. Changelly private key → server environment variable only (never in extension).
2. No secret in `manifest.json`, source maps, inline JS, or `browser.storage`.
3. All Changelly-authenticated calls go through backend proxy.
4. Extension never logs wallet addresses or amounts to telemetry without anonymization.
5. CSP in `manifest.json` allows `connect-src` only to our proxy host.
6. `host_permissions` is minimal: only proxy domain + Changelly's public static resources.

### Key Management (Backend)
- **Development:** `.env.local` with dummy/sandbox keys.
- **Staging:** secrets injected as environment variables by CI (GitHub Actions/Secrets).
- **Production:** secrets stored in a managed secret store (e.g., HashiCorp Vault or AWS
  Secrets Manager), loaded by the proxy service at startup — never written to disk.

### Replay Protection
- Each proxy request includes a `X-Request-Nonce: <uuid>` and `X-Request-Timestamp: <epoch-s>`.
- Backend rejects requests with timestamps older than 60 s or nonces already seen (Redis set,
  TTL = 60 s).

### Rate Limiting
- Backend: 60 quote requests / min per extension install ID (hashed, not the raw ID).
- 10 swap create / hour per install ID.
- 429 responses propagate to extension as degraded-mode banner.

### CSP for Extension
```json
"content_security_policy": {
  "extension_pages": "default-src 'self'; connect-src https://proxy.w3ai.io; img-src 'self' data: https://static.changelly.com; script-src 'self'"
}
```

---

## 7. Backend Proxy Service Architecture

### Stack
- TypeScript + Node.js 20 LTS
- Fastify 4 (fast, low overhead, schema-first)
- Zod for request/response validation
- Redis 7 for rate limiting, nonce deduplication, quote caching
- PostgreSQL 15 for swap history audit log (optional — can defer to Changelly as source of truth)
- Structured JSON logs (Pino)
- OpenTelemetry for metrics/tracing

### Endpoints

**GET /config/public**
- Request: none (auth: extension install ID via header)
- Response: `{ proxyVersion, supportedNetworks[], featureFlags, termsUrl }`
- Cache: 5 min, CDN-cacheable

**GET /assets**
- Response: paginated currency list with `{ id, name, symbol, iconUrl, enabled, blockchain }`

**GET /pairs?from=BTC&to=ETH**
- Response: `{ minAmount, maxAmount, available }`

**POST /quote/floating**
- Body: `{ from, to, amount }`
- Response: `{ estimatedAmount, rate, networkFee, ttlSeconds }`

**POST /quote/fixed**
- Body: `{ from, to, amount }`
- Response: `{ amountTo, rate, rateId, networkFee, ttlSeconds }`

**POST /validate/address**
- Body: `{ address, currency, extraId? }`
- Response: `{ result: boolean, message? }`

**POST /swap/create**
- Body: `{ from, to, amount, address, extraId?, rateType, rateId? }`
- Response: `{ id, payinAddress, expectedAmount, depositExtraId? }`

**GET /swap/:id**
- Response: full `TransactionDetail`

**GET /swap/:id/status**
- Response: `{ status, updatedAt }`

**GET /history?page=&limit=**
- Response: paginated `TransactionDetail[]` (from local DB or Changelly via proxy)

**POST /defi/intent**
- Body: `{ fromNetwork, fromToken, toNetwork, toToken, amount, walletAddress }`
- Response: `{ intentId, approvalRequired, approvalParams? }`

**POST /defi/approval-context**
- Body: `{ intentId }`
- Response: EIP-712 typed data or raw tx params for the wallet to sign

---

## 8. Data Models / TypeScript Interfaces

See `src/shared/types.ts` in the extension source for the complete set.

---

## 9. Implementation Milestones

| # | Milestone | Key Deliverables |
|---|---|---|
| M1 | Discovery + API verification | Changelly sandbox keys, API smoke tests, pair matrix |
| M2 | Backend proxy foundation | Fastify app, auth/signing, /config /assets /pairs |
| M3 | Extension shell + design system | manifest.json, popup shell, dark-mode tokens, router |
| M4 | Floating swap MVP | Quote, review, create, status tracking, receipt |
| M5 | Fixed-rate flow | Fixed quote TTL countdown, rateId lifecycle |
| M6 | DeFi integration (feature-flagged) | Wallet bridge, intent/approval/execution |
| M7 | History + recovery | Persistent state, restart recovery, receipt export |
| M8 | Security hardening | Nonce/replay protection, rate limiting, CSP audit |
| M9 | Firefox packaging | moz.build, jar.mn, build pipeline integration |
| M10 | QA + observability + launch | E2E tests, OTel dashboards, staging sign-off |

---

## 10. Definition of Done

- [ ] Extension packaged as built-in add-on in W3Ai Firefox build
- [ ] Remove button absent from about:addons; disable toggle present
- [ ] All Changelly API calls proxy-routed; zero secrets in extension JS
- [ ] Floating swap end-to-end works on stagingpoxy
- [ ] Fixed-rate swap end-to-end works
- [ ] Hold/KYC state handled with user-facing guidance
- [ ] Address validation covers major networks
- [ ] Quote refresh prevents stale execution
- [ ] Restart recovery tested
- [ ] CSP restricts connections to proxy domain only
- [ ] Unit test coverage ≥ 80% for all modules
- [ ] `npm audit` clean, no high/critical CVEs
- [ ] Structured logs, OTel metrics on backend
- [ ] Terms/Privacy links wired to legal URLs
- [ ] Localization placeholders wired to fluent (en-US baseline)
