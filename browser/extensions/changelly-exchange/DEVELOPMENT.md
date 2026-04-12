# Changelly Exchange Extension — Development Guide

Complete setup and workflow guide for local development of the Changelly Exchange WebExtension for W3Ai browser.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Initial Setup](#initial-setup)
4. [Development Workflow](#development-workflow)
5. [Building for Production](#building-for-production)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [Environment Configuration](#environment-configuration)

---

## Prerequisites

### Required
- **Node.js**: v20+ ([Download](https://nodejs.org/))
- **npm**: v10+ (included with Node.js)
- **macOS**: 12+
- **Firefox**: W3Ai build (`./mach run` from repo root)
- **Git**: For version control

### Optional
- **Redis**: For rate limiting (defaults to in-memory mock in development)
- **PostgreSQL**: For audit logs (optional, not required for development)
- **Docker**: For containerized local testing

---

## Project Structure

```
browser/extensions/changelly-exchange/
├── src/                           # Frontend extension code
│   ├── popup/                     # Popup UI (React)
│   │   ├── index.tsx
│   │   ├── styles/globals.css
│   │   └── index.html
│   ├── background/                # Background service worker
│   │   └── index.ts
│   ├── services/
│   │   └── proxy-client.ts        # HTTP client for /v1/* endpoints
│   ├── store/
│   │   └── AppStore.ts            # Redux store
│   └── tests/                     # Frontend tests
│       ├── proxy-client.test.ts
│       └── AppStore.test.ts
│
├── backend/                       # Backend proxy server
│   ├── src/
│   │   ├── index.ts               # Fastify app entry
│   │   ├── routes/                # API route handlers
│   │   │   ├── config.ts
│   │   │   ├── assets.ts
│   │   │   ├── quote.ts
│   │   │   ├── swap.ts
│   │   │   ├── history.ts
│   │   │   ├── pairs.ts
│   │   │   ├── defi.ts
│   │   │   └── feature-flags.ts
│   │   ├── security/              # Request signing
│   │   │   └── signer.ts
│   │   └── tests/                 # Backend tests
│   │       ├── jest.setup.ts
│   │       ├── routes/
│   │       │   ├── quote.test.ts
│   │       │   ├── swap.test.ts
│   │       │   └── all-endpoints.test.ts
│   │       └── security/
│   │           └── signer.test.ts
│   ├── .env.example               # Environment template (commit this)
│   ├── .env                       # Local config (DO NOT COMMIT)
│   ├── package.json
│   └── README.md
│
├── dist/                          # Built extension (generated)
│   ├── popup.js
│   ├── background/index.js
│   ├── manifest.json
│   ├── popup/index.html
│   └── styles/
│
├── manifest.json                  # WebExtension manifest (source)
├── webpack.config.js              # Webpack build config
├── jest.config.js                 # Frontend test config
├── package.json                   # Extension dependencies
├── DESIGN.md                      # Architecture & design
├── README.md                      # Extension overview
└── DEVELOPMENT.md                 # This file

```

---

## Initial Setup

### Step 1: Install Dependencies

```bash
# Navigate to extension directory
cd browser/extensions/changelly-exchange

# Install frontend dependencies
npm install

# Install backend dependencies
cd backend && npm install && cd ..
```

### Step 2: Configure Environment

```bash
# Create local .env file for backend
cd backend

# Copy template
cp .env.example .env

# Edit .env with your settings (values locked below for development mode)
# CHANGELLY_API_KEY=your_key_here         # Optional: replace for live testing
# CHANGELLY_API_SECRET=your_secret_here   # Optional: replace for live testing
```

**Default .env values for development:**
```env
PORT=3000
HOST=127.0.0.1
NODE_ENV=development
CHANGELLY_API_KEY=test_api_key_12345       # Test placeholder
CHANGELLY_API_SECRET=test_api_secret_67890 # Test placeholder
REDIS_URL=redis://localhost:6379           # Optional (mocked in dev)
```

### Step 3: Verify Installation

```bash
# Test frontend build
npm run build:dev
# Should see: "webpack 5.x.x compiled successfully"

# Test backend
cd backend
npm run typecheck
# Should exit with no errors
```

---

## Development Workflow

### Quick Start (5 minutes)

```bash
# Terminal 1: Start backend server
cd browser/extensions/changelly-exchange/backend
npm run dev
# Wait for: "[notification] build: /path/to/backend/src/index.ts"

# Terminal 2: Build extension with watch
cd browser/extensions/changelly-exchange
npm run dev
# Wait for: "webpack  compiled successfully"

# Terminal 3: Start Firefox
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

**Result:**
- Backend listening on `http://127.0.0.1:3000`
- Extension built to `dist/` folder
- Ready for live testing in browser

---

### Daily Development Cycle

#### 1. **Start Backend** (Terminal 1)

```bash
cd browser/extensions/changelly-exchange/backend
npm run dev

# Output should show:
# > tsx watch src/index.ts
# 1 file added
# ...
# [info] Server running at http://127.0.0.1:3000/
```

**What it does:**
- Watches `src/**/*.ts` for changes
- Auto-reloads on file save
- Hot-reload via `tsx watch`
- No restart required

---

#### 2. **Start Extension Watch** (Terminal 2)

```bash
cd browser/extensions/changelly-exchange
npm run dev

# Output should show:
# > webpack --mode development --watch
# webpack 5.x.x compiled ... in NNNs
# <i> [webpack.cache] build cache restored from /path/to/.webpack_cache
# [webpack.cache] ...
```

**What it does:**
- Watches `src/**/*.{ts,tsx,css}` for changes
- Rebuilds to `dist/` on save
- Auto-refresh in browser (manifest update triggers reload)

---

#### 3. **Start Browser** (Terminal 3)

```bash
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

**What it does:**
- Launches Firefox with W3Ai profile
- Auto-loads built-in add-ons from `browser/extensions/`
- Extension available immediately in browser

---

### Make a Change (Example: Fix API Endpoint)

1. **Edit source file:**
   ```bash
   # Terminal 2 is watching...
   vim browser/extensions/changelly-exchange/src/services/proxy-client.ts
   # Change 1 line
   ```

2. **Webpack auto-rebuilds:**
   ```
   [webpack.cache] ... 
   webpack 5.x.x compiled successfully in 234ms
   ```

3. **Browser auto-detects:**
   - Extension manifest updated
   - Content scripts reloaded
   - No page refresh needed

4. **Verify change:**
   - Open DevTools in browser (`F12`)
   - Check `Console` tab for any errors
   - Test new behavior

---

### Running Tests During Development

```bash
# Frontend tests (watch mode)
cd browser/extensions/changelly-exchange
npm test -- --watch

# Backend tests (watch mode)
cd browser/extensions/changelly-exchange/backend
npm test -- --watch
```

Each test file auto-runs on save. Useful for TDD (test-driven development).

---

## Building for Production

### Single Build

```bash
cd browser/extensions/changelly-exchange
npm run build

# Output: dist/ folder with minified assets
# ✓ popup.js (173 KiB, minimized)
# ✓ background/index.js (6.4 KiB, minimized)
# ✓ manifest.json
```

### Production Extension Package

```bash
# Package dist/ as .xpi (Firefox add-on format)
cd browser/extensions/changelly-exchange
zip -r changelly-exchange-v1.0.0.xpi dist/

# Ship changelly-exchange-v1.0.0.xpi to Add-ons store or internal update server
```

### Backend Production Build

```bash
cd browser/extensions/changelly-exchange/backend

# Build TypeScript to JavaScript
npm run build

# Output: dist/ folder with compiled .js files
# Start on production server:
# NODE_ENV=production npm start
```

---

## Testing

### Frontend Tests

```bash
cd browser/extensions/changelly-exchange

# Run all tests once
npm test

# Run in watch mode (re-run on file change)
npm test -- --watch

# Run specific test file
npm test -- proxy-client.test.ts

# Run with coverage
npm test -- --coverage
```

**Test Files:**
- `src/tests/proxy-client.test.ts` — HTTP client contract validation
- `src/tests/AppStore.test.ts` — Redux store logic

---

### Backend Tests

```bash
cd browser/extensions/changelly-exchange/backend

# Run all tests once
npm test

# Run in watch mode
npm test -- --watch

# Run specific test suite
npm test -- quote.test.ts

# Run all endpoints test
npm test -- all-endpoints.test.ts
```

**Test Suites:**
- `src/tests/routes/quote.test.ts` — Quote route validation
- `src/tests/routes/swap.test.ts` — Swap route validation
- `src/tests/routes/all-endpoints.test.ts` — Full endpoint coverage (12 endpoints)
- `src/tests/security/signer.test.ts` — Request signing security

---

### Live Smoke Testing

Test all endpoints against running backend with test credentials:

```bash
cd browser/extensions/changelly-exchange/backend

# Make sure backend is running (Terminal 1):
# npm run dev

# In a new terminal, run smoke test:
bash scripts/smoke-all-endpoints.sh

# Output:
# PASS  GET /v1/config
# PASS  GET /v1/assets
# PASS  GET /v1/feature-flags
# ... (12 endpoints total)
# All smoke checks completed.
```

---

### Integration Testing (With Real Credentials)

```bash
# Edit backend/.env with real Changelly API key + secret
vim backend/.env

# Restart backend:
cd browser/extensions/changelly-exchange/backend
npm run dev

# Run smoke test against real API:
bash scripts/smoke-all-endpoints.sh

# If using rate-limited APIs, stagger requests:
bash scripts/smoke-all-endpoints.sh --delay 1000  # 1s between requests
```

---

## Troubleshooting

### Issue: "CHANGELLY_API_KEY is required"

**Cause:** Backend `.env` not configured  
**Fix:**
```bash
cd browser/extensions/changelly-exchange/backend
cp .env.example .env
# Edit .env manually or use defaults
npm run dev
```

---

### Issue: "Backend not responding at :3000"

**Cause:** Port conflict or server crashed  
**Fix:**
```bash
# Check what's using port 3000
lsof -i :3000

# Kill conflicting process
kill -9 <PID>

# Restart backend
cd browser/extensions/changelly-exchange/backend
npm run dev
```

---

### Issue: "Extension not loading in browser"

**Cause:** Manifest error or build failure  
**Fix:**
```bash
# Verify build succeeded
ls browser/extensions/changelly-exchange/dist/manifest.json

# Check Firefox extensions page
about:debugging#/runtime/this-firefox

# Look for "changelly-exchange@w3ai.io" in list
# If missing, check browser console for load errors
```

---

### Issue: "webpack compiled but CSS not refreshing"

**Cause:** CSS cache or dev tools open  
**Fix:**
```bash
# Hard refresh browser
Cmd + Shift + R  (macOS)
Ctrl + Shift + R (Linux)

# Or restart browser:
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

---

### Issue: Tests failing with "Cannot find module"

**Cause:** Dependencies not installed or paths incorrect  
**Fix:**
```bash
cd browser/extensions/changelly-exchange
rm -rf node_modules package-lock.json
npm install

cd backend
rm -rf node_modules package-lock.json
npm install
```

---

## Environment Configuration

### Development (Local)

```env
NODE_ENV=development
PORT=3000
HOST=127.0.0.1

# Test credentials (no real API calls in dev mode)
CHANGELLY_API_KEY=test_api_key_12345
CHANGELLY_API_SECRET=test_api_secret_67890

# Optional services
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgresql://user:password@localhost:5432/changelly_proxy

ALLOWED_ORIGINS=moz-extension://
RATE_LIMIT_MAX=60
RATE_LIMIT_WINDOW_MS=60000
```

### Production

```env
NODE_ENV=production
PORT=3000         # Behind reverse proxy (Nginx)
HOST=0.0.0.0

# Real Changelly credentials (never in git)
CHANGELLY_API_KEY=<real-key-from-vault>
CHANGELLY_API_SECRET=<real-secret-from-vault>

# Production services
REDIS_URL=redis://redis-prod:6379
DATABASE_URL=postgresql://prod:pwd@db.internal:5432/changelly_proxy

ALLOWED_ORIGINS=https://proxy.w3ai.io
RATE_LIMIT_MAX=600
RATE_LIMIT_WINDOW_MS=60000
```

---

## Common Commands Reference

### Frontend (Extension)

| Command | Purpose |
|---------|---------|
| `npm install` | Install dependencies |
| `npm run dev` | Watch & rebuild on save |
| `npm run build` | Build for production |
| `npm run build:dev` | Build in dev mode (unminified) |
| `npm run typecheck` | Type-check without building |
| `npm run lint` | Run ESLint |
| `npm test` | Run Jest tests once |
| `npm test -- --watch` | Watch tests |

### Backend

| Command | Purpose |
|---------|---------|
| `npm install` | Install dependencies |
| `npm run dev` | Start with watch mode |
| `npm run build` | Compile TypeScript |
| `npm start` | Run compiled JS |
| `npm run typecheck` | Type-check |
| `npm run lint` | Lint code |
| `npm test` | Run tests once |
| `npm test -- --watch` | Watch tests |

### Browser

| Command | Purpose |
|---------|---------|
| `./mach run` | Start Firefox with extension |
| `./mach build` | Build W3Ai browser binary |

---

## Development Tips & Best Practices

### 1. **Use Redux DevTools**
Browser extension for debugging Redux state:
- Install: [Redux DevTools Extension](https://github.com/reduxjs/redux-devtools-extension)
- Open: `F12` → `Redux` tab

### 2. **Monitor Backend Logs**
Terminal 1 shows all requests:
```
{"level":30,"time":1776008217130,"reqId":"req-1","req":{"method":"GET","url":"/v1/config"},"msg":"incoming request"}
{"level":30,"time":1776008217141,"res":{"statusCode":200},"responseTime":10.46,"msg":"request completed"}
```

### 3. **Type-Safe API Contracts**
All routes use Zod schemas — type errors caught before runtime:
```typescript
// This will fail at startup if contract changes:
const response = await fetch('http://127.0.0.1:3000/v1/config');
// Response is guaranteed to match: ProxyConfigResponse type
```

### 4. **Test-Driven Development**
Write tests first, then implementation:
```bash
# 1. Write test
vim browser/extensions/changelly-exchange/src/tests/my-feature.test.ts

# 2. Run tests (fails)
npm test -- --watch

# 3. Implement feature
vim browser/extensions/changelly-exchange/src/my-feature.ts

# 4. Tests pass automatically
```

### 5. **Git Workflow**
```bash
# Always create feature branch
git checkout -b feature/my-feature

# Make changes
git add .
git commit -m "feat: implement my feature"

# Never commit .env files
git status  # Should NOT show backend/.env
```

---

## Next Steps

1. **Complete Initial Setup**
   ```bash
   cd browser/extensions/changelly-exchange
   npm install
   cd backend && npm install && cd ..
   ```

2. **Start Development**
   ```bash
   # Terminal 1: Backend
   cd backend && npm run dev
   
   # Terminal 2: Frontend
   npm run dev
   
   # Terminal 3: Browser
   ./mach run
   ```

3. **Make Your First Change**
   - Edit `src/services/proxy-client.ts`
   - Save and watch it auto-rebuild
   - Test in browser

4. **Run Tests Frequently**
   ```bash
   npm test  # Every commit
   ```

---

## Support

For issues or questions:
- Check [Troubleshooting](#troubleshooting) section
- Review test output: `npm test -- --verbose`
- Check backend logs in Terminal 1
- Open browser DevTools: `F12`

**Happy coding!** 🚀
