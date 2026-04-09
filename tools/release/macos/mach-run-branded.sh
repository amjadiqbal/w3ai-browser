#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mach-run.sh [options]

Wrapper for ./mach run that ensures W3Ai branding is properly applied.

This script ensures that:
1. The application is built with W3Ai branding
2. Icons and assets are properly packaged into the .app bundle
3. System caches are cleared so new branding is displayed
4. The application is launched

Options:
  --repackage-only   Only repackage, don't run afterward
  --help             Show this help message

How it works:
1. Calls ./mach build to ensure latest code is compiled
2. Calls ./mach repackage to copy W3Ai icons/assets to .app bundle
3. Clears macOS app cache so the new branding is visible in Finder/Dock
4. Launches the app with ./mach run

This ensures the W3Ai logo (not Firefox) appears in Finder, Dock, and window titles.
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
REPACKAGE_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repackage-only)
      REPACKAGE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # Pass remaining args to mach run
      break
      ;;
  esac
done

cd "$ROOT_DIR"

# Verify branding configuration
if ! grep -q "w3ai" mozconfig; then
  echo "[!] WARNING: W3Ai branding not configured in mozconfig" >&2
  echo "[!] Add this line to mozconfig:" >&2
  echo "    ac_add_options --with-branding=browser/branding/w3ai" >&2
  exit 1
fi

echo "=========================================="
echo "W3Ai Browser - Preparing with Branding"
echo "=========================================="
echo ""

echo "[1/3] Building W3Ai application"
./mach build
echo "[✓] Build complete"
echo ""

echo "[2/3] Repackaging with W3Ai branding assets"
./mach repackage
echo "[✓] Branding assets packaged"
echo ""

echo "[3/3] Clearing macOS app icon cache"
# Clear various macOS caches to ensure new branding is visible
killall Finder 2>/dev/null || true
sleep 1
killall Dock 2>/dev/null || true
sleep 1
echo "[✓] Cache cleared"
echo ""

if [[ "$REPACKAGE_ONLY" == "true" ]]; then
  echo "=========================================="
  echo "✓ W3Ai branding repackaged"
  echo "=========================================="
  echo ""
  echo "To run W3Ai Browser:"
  echo "  ./mach run"
  echo ""
  exit 0
fi

echo "=========================================="
echo "✓ Launching W3Ai Browser"
echo "=========================================="
echo ""

# Run with W3Ai branding
./mach run "$@"
