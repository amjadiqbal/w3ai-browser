#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build-prod.sh [options]

Build, sign, and notarize W3Ai for macOS production distribution.
Generates a fully notarized DMG ready for release.

Options:
  --objdir <path>               Optional object directory for output
  --dmg <path>                  Explicit DMG path (skips auto-detect)
  --keychain-profile <name>     notarytool keychain profile name
  --apple-id <id>               Apple ID (if not using keychain profile)
  --team-id <id>                Apple Developer Team ID
  --signing-identity <name>     Optional DMG signing identity
  --no-notarize                 Build and sign, but skip notarization
  --help                        Show this help message

Output:
  - Builds W3Ai application binary with optimizations
  - Packages into .app bundle with W3Ai branding
  - Creates .dmg installer
  - Signs the DMG
  - Submits to Apple for notarization
  - Waits for notarization approval
  - Staples notarization to DMG

Requirements:
  - Apple Developer account with notarization credentials
  - codesign CLI tools installed (via Xcode)
  - xcrun notarytool configured

Note:
  Notarization typically takes 5-15 minutes.
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
OBJ_DIR=""
DMG_PATH=""
KEYCHAIN_PROFILE=""
APPLE_ID=""
TEAM_ID=""
SIGNING_IDENTITY=""
SKIP_NOTARIZE=false
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --objdir)
      OBJ_DIR="${2:-}"
      shift 2
      ;;
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --keychain-profile)
      KEYCHAIN_PROFILE="${2:-}"
      shift 2
      ;;
    --apple-id)
      APPLE_ID="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY="${2:-}"
      shift 2
      ;;
    --no-notarize)
      SKIP_NOTARIZE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
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
echo "W3Ai macOS Production Build"
echo "=========================================="
echo ""

echo "[1/4] Building application"
./mach build
echo "[✓] Build complete"
echo ""

echo "[2/4] Packaging application"
./mach package
echo "[✓] Package complete"
echo ""

echo "[3/4] Repackaging for DMG"
./mach repackage

if [[ -z "$DMG_PATH" ]]; then
  if [[ -n "$OBJ_DIR" ]]; then
    DMG_PATH="$(ls -t "$OBJ_DIR"/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  else
    DMG_PATH="$(ls -t obj-*/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  fi
fi

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "[✗] Error: DMG not found" >&2
  exit 1
fi

echo "[✓] Detected DMG: $DMG_PATH"
echo ""

if [[ "$SKIP_NOTARIZE" == "true" ]]; then
  echo "[4/4] Signing DMG (--no-notarize specified, skipping notarization)"
  
  SIGN_ARGS=("--dmg" "$DMG_PATH")
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    SIGN_ARGS+=("--signing-identity" "$SIGNING_IDENTITY")
  fi
  
  "$ROOT_DIR/tools/release/macos/sign-and-notarize-dev.sh" "${SIGN_ARGS[@]}"
  
  echo ""
  echo "=========================================="
  echo "✓ Build and signing complete (notarization skipped)"
  echo "=========================================="
else
  echo "[4/4] Signing and notarizing DMG"
  
  NOTARIZE_ARGS=("--dmg" "$DMG_PATH")
  
  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    NOTARIZE_ARGS+=("--keychain-profile" "$KEYCHAIN_PROFILE")
  else
    if [[ -n "$APPLE_ID" ]]; then
      NOTARIZE_ARGS+=("--apple-id" "$APPLE_ID")
    fi
    if [[ -n "$TEAM_ID" ]]; then
      NOTARIZE_ARGS+=("--team-id" "$TEAM_ID")
    fi
  fi
  
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    NOTARIZE_ARGS+=("--signing-identity" "$SIGNING_IDENTITY")
  fi
  
  NOTARIZE_ARGS+=("${EXTRA_ARGS[@]}")
  
  "$ROOT_DIR/tools/release/macos/sign-and-notarize-dev.sh" "${NOTARIZE_ARGS[@]}"
  
  echo ""
  echo "=========================================="
  echo "✓ Production build complete"
  echo "=========================================="
fi

echo ""
echo "DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"
echo ""
