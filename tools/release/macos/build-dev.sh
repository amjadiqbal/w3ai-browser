#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build-dev.sh [options]

Build W3Ai for macOS development (no notarization notarization).
Generates an unsigned DMG suitable for testing on development devices.

Options:
  --objdir <path>       Optional object directory for output
  --no-dmg              Build only, skip DMG packaging
  --help                Show this help message

Output:
  - Builds W3Ai application binary
  - Packages into standalone .app bundle with W3Ai branding
  - Creates .dmg installer (unless --no-dmg is specified)
  - All W3Ai branding assets (icons, logos) are included
  - DMG is NOT signed or notarized
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
OBJ_DIR=""
SKIP_DMG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --objdir)
      OBJ_DIR="${2:-}"
      shift 2
      ;;
    --no-dmg)
      SKIP_DMG=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

# Ensure mozconfig uses W3Ai branding
if ! grep -q "w3ai" mozconfig; then
  echo "[!] WARNING: mozconfig does not specify w3ai branding" >&2
  echo "[!] Verify --with-branding=browser/branding/w3ai is set" >&2
fi

echo "=========================================="
echo "W3Ai macOS Development Build"
echo "=========================================="
echo ""

echo "[1/3] Building application"
./mach build
echo "[✓] Build complete"
echo ""

echo "[2/3] Packaging application"
./mach package
echo "[✓] Package complete"
echo ""

if [[ "$SKIP_DMG" == "false" ]]; then
  echo "[3/3] Repackaging for DMG"
  ./mach repackage
  
  if [[ -z "$OBJ_DIR" ]]; then
    DMG_PATH="$(ls -t obj-*/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  else
    DMG_PATH="$(ls -t "$OBJ_DIR"/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -n "$DMG_PATH" && -f "$DMG_PATH" ]]; then
    echo "[✓] DMG ready: $DMG_PATH"
    ls -lh "$DMG_PATH"
  else
    echo "[!] DMG not found" >&2
  fi
else
  echo "[3/3] Skipping DMG (--no-dmg specified)"
fi

echo ""
echo "=========================================="
echo "✓ Development build complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  - Mount the .dmg and install W3Ai"
echo "  - Test on your device to verify branding and features"
echo "  - Use ./mach run to test directly from the build directory"
echo ""
