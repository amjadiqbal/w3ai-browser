# Quick Start Reference — Changelly Exchange Development

**One-time setup, then daily 3-terminal workflow for smooth development.**

---

## 🚀 Initial Setup (One Time)

### Run Setup Script
```bash
cd browser/extensions/changelly-exchange
bash setup.sh
```

**What it does:**
- ✓ Checks Node.js version (20+)
- ✓ Installs frontend dependencies
- ✓ Installs backend dependencies  
- ✓ Creates backend `.env` file (auto-configured)
- ✓ Verifies builds compile without errors
- ✓ Generates startup guide

**Expected output:**
```
✓ Setup Complete!

Next Steps: Read DEVELOPMENT.md or start 3 terminals below...
```

---

## 📺 Daily Development (3 Terminals)

### Terminal 1: Backend Server (Port 3000)
```bash
cd browser/extensions/changelly-exchange/backend
npm run dev
```

**Wait for this message:**
```
[info] Server running at http://127.0.0.1:3000/
```

**Features:**
- ✓ Auto-reloads on file save
- ✓ Shows request logs in terminal
- ✓ Type-checked on startup

---

### Terminal 2: Extension Watch Mode
```bash
cd browser/extensions/changelly-exchange
npm run dev
```

**Wait for this message:**
```
webpack 5.x.x compiled successfully in NNNms
```

**Features:**
- ✓ Auto-rebuilds on file save
- ✓ Outputs to `dist/` folder
- ✓ Browser auto-detects changes

---

### Terminal 3: Browser Launch
```bash
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

**Extension appears in ~30 seconds:**
- ✓ "W3Ai Exchange" button in toolbar
- ✓ Backend responding on port 3000
- ✓ Ready for testing

---

## ✅ Verify Everything Works

### Test 1: Backend Responds
```bash
curl http://127.0.0.1:3000/v1/config | json_pp
```

**Expected output:**
```json
{
  "proxyVersion": "v1",
  "environment": "development",
  "maintenanceMode": false,
  ...
}
```

### Test 2: Run Tests
```bash
# Terminal 4: Extension tests
cd browser/extensions/changelly-exchange
npm test

# Result: 16/16 tests PASS ✓

# Terminal 5: Backend tests
cd browser/extensions/changelly-exchange/backend
npm test

# Result: 27/27 tests PASS ✓
```

### Test 3: Smoke Test All Endpoints
```bash
cd browser/extensions/changelly-exchange/backend
bash scripts/smoke-all-endpoints.sh
```

**Expected output:**
```
PASS  GET /v1/config
PASS  GET /v1/assets
...
All smoke checks completed. ✓
```

---

## 💻 Make Your First Change

### 1. Edit a File
```bash
vim browser/extensions/changelly-exchange/src/services/proxy-client.ts
# Change 1 line
# Save (Cmd+Z or Ctrl+S in editor)
```

### 2. Watch Auto-Build in Terminal 2
```
webpack 5.x.x compiled successfully in 234ms
```

### 3. Use in Browser
- Open DevTools: `F12` → Console
- Check for errors
- Test new behavior

---

## 🛠 Common Tasks

### Format Code
```bash
cd browser/extensions/changelly-exchange
npm run lint  # Show issues

cd backend
npm run lint  # Show issues
```

### Type Check (Without Building)
```bash
npm run typecheck  # Frontend
cd backend && npm run typecheck  # Backend
```

### Clean Build
```bash
# Remove build outputs
rm -rf dist
rm -rf browser/extensions/changelly-exchange/backend/dist

# Rebuild
npm run build
cd backend && npm run build
```

### Test with Real Changelly Credentials
```bash
# 1. Get API key/secret from Changelly dashboard
# 2. Edit backend/.env
vim backend/backend/.env

# Change:
# CHANGELLY_API_KEY=your_real_key
# CHANGELLY_API_SECRET=your_real_secret

# 3. Restart backend (Terminal 1: Ctrl+C, then npm run dev)

# 4. Run smoke test
bash backend/scripts/smoke-all-endpoints.sh
```

---

## 🐛 Troubleshooting

### Backend won't start
```bash
# Check .env exists
ls browser/extensions/changelly-exchange/backend/.env

# If missing, create from template:
cd browser/extensions/changelly-exchange/backend
cp .env.example .env
```

### Port 3000 in use
```bash
# Find what's using port
lsof -i :3000

# Kill it
kill -9 <PID>

# Restart backend
npm run dev
```

### Extension not appearing
```bash
# Check build succeeded
ls browser/extensions/changelly-exchange/dist/manifest.json

# Open Firefox extensions page
about:debugging

# Look for "changelly-exchange@w3ai.io" (should be Active)
```

### Tests failing
```bash
# Reinstall dependencies
cd browser/extensions/changelly-exchange
rm -rf node_modules package-lock.json
npm install

cd backend
rm -rf node_modules package-lock.json
npm install
```

### CSS not updating
```bash
# Hard refresh browser
Cmd+Shift+R  (macOS)

# Or restart browser
cd /Volumes/Amjad/Plato/W3Ai
./mach run
```

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | **Complete development guide** ← Start here! |
| [README.md](README.md) | Project overview & quick reference |
| [DESIGN.md](DESIGN.md) | Architecture & design decisions |
| [backend/README.md](backend/README.md) | Backend setup & deployment |

---

## 🎯 Daily Checklist

- [ ] Start Backend (Terminal 1): `npm run dev` in backend/
- [ ] Start Extension Watch (Terminal 2): `npm run dev` in extension/
- [ ] Start Browser (Terminal 3): `./mach run` from repo root
- [ ] Verify backend at http://127.0.0.1:3000/v1/config
- [ ] Make changes, save, watch auto-rebuild
- [ ] Run tests before commit: `npm test`
- [ ] Commit with message: `git commit -m "feat: description"`

---

## ⚙️ Environment Files

### `.env` (Backend Local Config)
```
PORT=3000
NODE_ENV=development
CHANGELLY_API_KEY=test_api_key_12345
CHANGELLY_API_SECRET=test_api_secret_67890
```

**NEVER commit this file.** It's in `.gitignore` automatically.

### `.env.example` (Template — Committed to git)
```
# Copy this to .env and fill in your values
CHANGELLY_API_KEY=your_api_key_here
CHANGELLY_API_SECRET=your_api_secret_here
```

---

## 🔧 File Locations

```
Important files to know:

Frontend:
  src/services/proxy-client.ts      → HTTP client for API routes
  src/store/AppStore.ts             → Redux state management
  src/popup/index.tsx               → Main UI component
  src/background/index.ts           → Service worker/background script

Backend:
  backend/src/index.ts              → Fastify app entry point
  backend/src/routes/*.ts           → API route handlers
  backend/src/security/signer.ts    → Request signing logic
  backend/.env                      → Local configuration (ignored by git)
  backend/.env.example              → Template (committed)

Config:
  manifest.json                     → WebExtension manifest
  webpack.config.js                 → Build configuration
  jest.config.js                    → Test configuration
  backend/jest.config.json          → Backend test config

Documentation:
  DEVELOPMENT.md                    → Full development guide
  README.md                         → Project overview
  DESIGN.md                         → Architecture
```

---

## 💡 Pro Tips

1. **Keep terminals open** — You'll go back to them dozens of times daily
2. **Use `npm test -- --watch`** — Auto-runs tests on file changes  
3. **Check browser DevTools** — Console shows errors from extension
4. **Monitor Terminal 1 logs** — Shows every API request + response times
5. **Commit often** — Small commits are easier to debug

---

## 📞 Need Help?

1. **Most questions answered in:** [DEVELOPMENT.md](DEVELOPMENT.md)
2. **Type errors?** Run: `npm run typecheck`
3. **Tests failing?** Run: `npm test -- --verbose`
4. **Backend issues?** Check Terminal 1 logs
5. **Extension issues?** Check browser DevTools (F12)

---

**Ready?** Run setup.sh, open 3 terminals, and start coding! 🚀
