# Changelly Exchange Web Extension

**Real-time cryptocurrency exchange built into W3Ai Browser**

A WebExtension that integrates the Changelly Exchange API into W3Ai browser, enabling seamless crypto asset swaps without leaving the browser.

---

## Features

✅ **Instant Quotes** — Real-time buy/sell rates via Changelly API  
✅ **Secure Swaps** — Backend-signed requests protect API credentials  
✅ **DeFi Swaps** — Decentralized swap routing via Changelly DeFi API  
✅ **Rate Limiting** — Intelligent request throttling (60 req/min default)  
✅ **Multi-Asset** — 100+ cryptocurrencies supported  
✅ **Built-in** — No installation required in W3Ai  
✅ **Type-Safe** — Full TypeScript + Zod runtime validation  
✅ **Tested** — 43 automated tests (frontend + backend)  

---

## Quick Start

### For Users

The extension is **built into W3Ai Browser** and auto-loads on startup.

1. **Launch W3Ai:**
   ```bash
   cd /Volumes/Amjad/Plato/W3Ai
   ./mach run
   ```

2. **Open Extension:**
   - Click **W3Ai Exchange** button in toolbar
   - Select currencies and amount
   - Review quote and confirm swap

### For Developers

**See [DEVELOPMENT.md](DEVELOPMENT.md)** for complete setup and development workflow.

**Quick Setup (5 minutes):**

```bash
# Terminal 1: Backend
cd browser/extensions/changelly-exchange/backend
npm install
cp .env.example .env
npm run dev

# Terminal 2: Extension (watch mode)
cd browser/extensions/changelly-exchange
npm install
npm run dev

# Terminal 3: Browser
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

---

## Project Structure

```
browser/extensions/changelly-exchange/
├── src/                    # Frontend extension (React + TypeScript)
├── backend/                # Backend proxy server (Fastify)
├── dist/                   # Compiled extension (auto-generated)
├── DEVELOPMENT.md          # Complete dev guide (START HERE)
├── DESIGN.md               # Architecture & design decisions
├── manifest.json           # WebExtension manifest (MV2)
└── webpack.config.js       # Build configuration
```

---

## Architecture

### Extension (Frontend)
- **Language:** React + TypeScript
- **Bundler:** Webpack 5
- **State:** Redux
- **API Client:** Proxy client (`src/services/proxy-client.ts`)
- **Build Output:** `dist/` folder

### Backend (Proxy Server)
- **Framework:** Fastify
- **Language:** TypeScript
- **Validation:** Zod schemas
- **Security:** HMAC-SHA256 request signing
- **Rate Limiting:** Redis-backed throttling
- **Port:** 3000 (local dev)

### API Routes (`/v1/*`)
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/config` | GET | Server configuration & maintenance status |
| `/assets` | GET | Supported cryptocurrency list |
| `/pairs` | GET | Tradeable pairs and limits |
| `/feature-flags` | GET | Feature toggles (DeFi, etc.) |
| `/quote/floating` | POST | Get floating rate quote |
| `/quote/fixed` | POST | Get fixed rate quote |
| `/swap` | POST | Create new swap transaction |
| `/swap/status` | GET | Check swap status by ID |
| `/swap/detail` | GET | Get full swap details |
| `/history` | GET | User swap history |
| `/validate-address` | POST | Validate recipient address |
| `/defi/*` | POST/GET | DeFi swap routes and execution |

---

## Environment Setup

### Local Development (.env)

```bash
cd backend
cp .env.example .env
# Edit .env with your settings
```

**Default values (test mode):**
```env
PORT=3000
HOST=127.0.0.1
NODE_ENV=development
CHANGELLY_API_KEY=test_api_key_12345
CHANGELLY_API_SECRET=test_api_secret_67890
```

**For live testing (real API):**
```env
CHANGELLY_API_KEY=your_real_key
CHANGELLY_API_SECRET=your_real_secret
```

**IMPORTANT:** `.env` is ignored by git — credentials never committed.

---

## Testing

### Frontend Tests
```bash
cd browser/extensions/changelly-exchange
npm test              # Run once
npm test -- --watch  # Watch mode (TDD)
```

**Coverage:** Proxy client, Redux store, UI components

### Backend Tests
```bash
cd browser/extensions/changelly-exchange/backend
npm test              # Run once  
npm test -- --watch  # Watch mode
```

**Coverage:** Quote routes, swap routes, all endpoints, security signing

### Smoke Tests (Full Integration)
```bash
cd browser/extensions/changelly-exchange/backend
npm run dev         # Terminal 1: Start server

# Terminal 2:
bash scripts/smoke-all-endpoints.sh

# Output:
# PASS  GET /v1/config
# PASS  GET /v1/assets
# ... (12 total endpoints)
```

---

## Building for Production

### Extension
```bash
cd browser/extensions/changelly-exchange
npm run build
# Output: dist/ (minified, optimized)
# Package as: dist/ → changelly-exchange.xpi
```

### Backend
```bash
cd browser/extensions/changelly-exchange/backend
npm run build
npm start  # NODE_ENV=production
```

---

## Key Files

| File | Purpose |
|------|---------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | **Complete development guide — START HERE** |
| [DESIGN.md](DESIGN.md) | Architecture decisions & component breakdown |
| [backend/README.md](backend/README.md) | Backend-specific setup & deployment |
| [manifest.json](manifest.json) | WebExtension manifest (MV2 format) |
| [src/services/proxy-client.ts](src/services/proxy-client.ts) | HTTP client for /v1/* routes |
| [backend/src/index.ts](backend/src/index.ts) | Fastify app entry point |

---

## Troubleshooting

### Extension not appearing in browser
✓ It's built-in and hidden by design (check `about:debugging`)  
✓ Verify: `changelly-exchange@w3ai.io` is **Active** in Extensions DB

### Backend won't start
✓ Check: `.env` file exists with `CHANGELLY_API_KEY` and `CHANGELLY_API_SECRET`  
```bash
cd backend && cp .env.example .env
```

### Tests failing
✓ Reinstall dependencies:
```bash
rm -rf node_modules package-lock.json
npm install
```

### Port 3000 already in use
```bash
lsof -i :3000
kill -9 <PID>
npm run dev  # Restart
```

**See [DEVELOPMENT.md#Troubleshooting](DEVELOPMENT.md#troubleshooting) for more help.**

---

## Development Workflow

### Daily Development (3 Terminals)
```bash
# Terminal 1: Backend (watch mode — auto-reloads on save)
cd backend && npm run dev

# Terminal 2: Extension (watch mode — auto-rebuilds on save)
npm run dev

# Terminal 3: Browser
cd /Volumes/Amjad/Plato/W3Ai && ./mach run
```

### Code Changes Flow
1. Edit source file (`src/**/*.ts` or `backend/src/**/*.ts`)
2. Webpack/tsx auto-rebuilds ✓
3. Browser hot-reloads (manifest update detected) ✓
4. No manual restart needed ✓

### Test-Driven Development
```bash
# Terminal: Watch tests
npm test -- --watch

# Edit code → tests auto-run
# Green = good to commit
```

---

## Security

✅ **API Credentials:** Stored in `.env` (ignored by git, never exposed to frontend)  
✅ **Request Signing:** Backend signs all Changelly API requests (HMAC-SHA256)  
✅ **Rate Limiting:** Redis-backed throttling prevents abuse  
✅ **CORS:** Extension origin only (`moz-extension://`)  
✅ **CSP:** Content Security Policy enforced per manifest  
✅ **Type Safety:** Zod runtime validation on all routes  

---

## Performance

- **Extension Bundle:** 187 KiB (React + Redux + styles)
- **Background Worker:** 6.4 KiB (auto-updates, monitoring)
- **Backend Response:** <100ms (cached data) to <500ms (API calls)
- **Rate Limiting:** Configurable (default: 60 req/min per IP)

---

## Contributing

1. Create feature branch:
   ```bash
   git checkout -b feature/my-feature
   ```

2. Follow development workflow (see above)

3. Run tests before commit:
   ```bash
   npm test  # Frontend
   cd backend && npm test  # Backend
   ```

4. Commit with conventional messages:
   ```bash
   git commit -m "feat: add new swap feature"
   ```

5. Push to origin:
   ```bash
   git push origin feature/my-feature
   ```

---

## License

Copyright © W3Ai. All rights reserved.

---

## Support

- **Dev Guide:** [DEVELOPMENT.md](DEVELOPMENT.md)
- **Design:** [DESIGN.md](DESIGN.md)
- **Backend Setup:** [backend/README.md](backend/README.md)
- **Smoke Tests:** `bash backend/scripts/smoke-all-endpoints.sh`

**Questions?** Check [DEVELOPMENT.md#Troubleshooting](DEVELOPMENT.md#troubleshooting) or review test output for clues.
