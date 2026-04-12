#!/bin/bash

# Changelly Exchange Extension — Automated Setup Script
# Handles all initial configuration for smooth development

set -e  # Exit on first error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Changelly Exchange Extension — Setup Script${NC}"
echo -e "${BLUE}============================================${NC}\n"

# Check Node.js version
echo -e "${BLUE}[1/6]${NC} Checking Node.js version..."
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found. Please install Node.js 20+ from https://nodejs.org/${NC}"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo -e "${RED}✗ Node.js 20+ required (you have $(node -v))${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js $(node -v) detected${NC}\n"

# Install frontend dependencies
echo -e "${BLUE}[2/6]${NC} Installing frontend dependencies..."
cd "$PROJECT_ROOT"
if [ ! -d "node_modules" ]; then
    npm install --legacy-peer-deps > /dev/null 2>&1
    echo -e "${GREEN}✓ Frontend dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Frontend dependencies already installed${NC}"
fi
echo ""

# Install backend dependencies
echo -e "${BLUE}[3/6]${NC} Installing backend dependencies..."
cd "$PROJECT_ROOT/backend"
if [ ! -d "node_modules" ]; then
    npm install --legacy-peer-deps > /dev/null 2>&1
    echo -e "${GREEN}✓ Backend dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Backend dependencies already installed${NC}"
fi
cd "$PROJECT_ROOT"
echo ""

# Configure .env file
echo -e "${BLUE}[4/6]${NC} Configuring backend environment..."
if [ ! -f "$PROJECT_ROOT/backend/.env" ]; then
    cp "$PROJECT_ROOT/backend/.env.example" "$PROJECT_ROOT/backend/.env"
    cat > "$PROJECT_ROOT/backend/.env" << 'EOF'
# Local .env for development — NEVER commit this file
PORT=3000
HOST=127.0.0.1
NODE_ENV=development

# Test Changelly API Credentials
# Replace with real credentials for live testing:
#   CHANGELLY_API_KEY=your_real_key
#   CHANGELLY_API_SECRET=your_real_secret
CHANGELLY_API_KEY=test_api_key_12345
CHANGELLY_API_SECRET=test_api_secret_67890
CHANGELLY_API_BASE_URL=https://api.changelly.com/v2

# Changelly DeFi Swap API
CHANGELLY_DEFI_BASE_URL=https://dex-api.changelly.com/v1

# Redis for local testing (optional for rate limiting)
REDIS_URL=redis://localhost:6379

# PostgreSQL for audit log (optional)
DATABASE_URL=postgresql://user:password@localhost:5432/changelly_proxy

# CORS origins
ALLOWED_ORIGINS=moz-extension://

# Rate limits
RATE_LIMIT_MAX=60
RATE_LIMIT_WINDOW_MS=60000
EOF
    echo -e "${GREEN}✓ Created backend/.env with default configuration${NC}"
else
    echo -e "${GREEN}✓ backend/.env already exists${NC}"
fi
echo ""

# Verify builds
echo -e "${BLUE}[5/6]${NC} Verifying builds..."

# Frontend typecheck
if npm run typecheck > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Frontend type check passed${NC}"
else
    echo -e "${YELLOW}⚠ Frontend type errors detected (non-blocking)${NC}"
fi

# Backend typecheck
cd "$PROJECT_ROOT/backend"
if npm run typecheck > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Backend type check passed${NC}"
else
    echo -e "${YELLOW}⚠ Backend type errors detected (non-blocking)${NC}"
fi
cd "$PROJECT_ROOT"
echo ""

# Create startup guide
echo -e "${BLUE}[6/6]${NC} Generating startup guide..."
cat > "$PROJECT_ROOT/.startup-guide.sh" << 'EOF'
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
EOF
chmod +x "$PROJECT_ROOT/.startup-guide.sh"
echo -e "${GREEN}✓ Startup guide created (.startup-guide.sh)${NC}"
echo ""

# Summary
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${BLUE}============================================${NC}\n"

echo -e "Next Steps:\n"
echo -e "  ${YELLOW}1. Read the Complete Guide:${NC}"
echo -e "     open DEVELOPMENT.md  (or: cat DEVELOPMENT.md)\n"

echo -e "  ${YELLOW}2. Start Development (3 Terminals):${NC}"
echo -e "     Terminal 1: cd backend && npm run dev"
echo -e "     Terminal 2: npm run dev"
echo -e "     Terminal 3: cd /Volumes/Amjad/Plato/W3Ai && ./mach run\n"

echo -e "  ${YELLOW}3. Test Your Setup:${NC}"
echo -e "     # After Terminal 1 is ready, try:"
echo -e "     curl http://127.0.0.1:3000/v1/config\n"

echo -e "  ${YELLOW}4. Run Tests:${NC}"
echo -e "     npm test              # Frontend"
echo -e "     cd backend && npm test # Backend\n"

echo -e "  ${YELLOW}5. For Real API Testing:${NC}"
echo -e "     # Edit backend/.env and add real Changelly credentials"
echo -e "     vim backend/.env\n"

echo -e "${BLUE}Questions?${NC} See DEVELOPMENT.md for complete guide\n"
