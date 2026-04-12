#!/bin/bash

# W3Ai Changelly Exchange — Quick Start Guide
# Fork this into 3 terminals to start development

echo "
╔════════════════════════════════════════════════════════════════════╗
║     Changelly Exchange Extension — Quick Start (3 Terminals)       ║
╚════════════════════════════════════════════════════════════════════╝

TERMINAL 1 — Backend API Server:
  cd browser/extensions/changelly-exchange/backend
  npm run dev
  # Waits for: [info] Server running at http://127.0.0.1:3000/

TERMINAL 2 — Frontend Watch Mode:
  cd browser/extensions/changelly-exchange
  npm run dev
  # Waits for: webpack 5.x.x compiled successfully

TERMINAL 3 — Browser:
  cd /Volumes/Amjad/Plato/W3Ai
  ./mach run
  # Extension auto-loads after ~30 seconds

═════════════════════════════════════════════════════════════════════

✓ Extension will appear in browser as 'W3Ai Exchange' button
✓ Backend at http://127.0.0.1:3000 (see Terminal 1 logs)
✓ Changes auto-rebuild (no manual steps needed)
✓ Open browser DevTools: F12 → Console to see errors

═════════════════════════════════════════════════════════════════════

TEST ENDPOINTS:
  curl http://127.0.0.1:3000/v1/config
  curl http://127.0.0.1:3000/v1/assets
  curl http://127.0.0.1:3000/v1/feature-flags

RUN TESTS:
  # Terminal 1: Extension tests
  npm test

  # Terminal 2: Backend tests  
  cd backend && npm test

  # Full smoke test
  bash backend/scripts/smoke-all-endpoints.sh

═════════════════════════════════════════════════════════════════════
"
