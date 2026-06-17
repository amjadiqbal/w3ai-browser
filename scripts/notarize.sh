#!/usr/bin/env bash
# notarize.sh — codesign, notarize, and staple TMRW W3 Browser for distribution
#
# Prerequisites:
#   1. Xcode Command Line Tools installed (xcode-select --install)
#   2. Valid "Developer ID Application" certificate in your keychain
#   3. .env file at repo root with all APPLE_* variables filled in
#
# Usage:
#   ./scripts/notarize.sh              # uses .env from repo root
#   APP_PATH="/path/to/App.app" ./scripts/notarize.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Load .env ──────────────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# ── Validate required vars ─────────────────────────────────────────────────────
required_vars=(
  APPLE_ID
  APPLE_APP_SPECIFIC_PASSWORD
  APPLE_TEAM_ID
  APPLE_BUNDLE_ID
  APPLE_SIGNING_IDENTITY
)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

# ── Resolve app path ───────────────────────────────────────────────────────────
APP_PATH="${APP_PATH:-$REPO_ROOT/$BUILT_APP_PATH}"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: App not found at: $APP_PATH"
  echo "Run './mach build' first, or set APP_PATH=/path/to/TMRW W3 Browser.app"
  exit 1
fi

DMG_PATH="${APP_PATH%.app}.dmg"
ZIP_PATH="${APP_PATH%.app}-notarize.zip"

echo "==> App:    $APP_PATH"
echo "==> Bundle: $APPLE_BUNDLE_ID"
echo "==> Signer: $APPLE_SIGNING_IDENTITY"
echo ""

# ── Step 1: Deep codesign ──────────────────────────────────────────────────────
echo "==> [1/5] Codesigning..."
codesign \
  --deep \
  --force \
  --verify \
  --verbose=2 \
  --timestamp \
  --options runtime \
  --entitlements "$REPO_ROOT/browser/branding/w3ai/entitlements.plist" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_PATH"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec --verbose "$APP_PATH"

# ── Step 2: Create zip for notarization ───────────────────────────────────────
echo ""
echo "==> [2/5] Creating zip for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── Step 3: Submit to Apple Notary Service ────────────────────────────────────
echo ""
echo "==> [3/5] Submitting to Apple Notary Service (this takes 1-5 minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --timeout 600

# ── Step 4: Staple notarization ticket ────────────────────────────────────────
echo ""
echo "==> [4/5] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ── Step 5: Create distributable DMG ──────────────────────────────────────────
echo ""
echo "==> [5/5] Creating DMG..."
if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "TMRW W3 Browser" \
    --window-size 600 400 \
    --icon-size 128 \
    --app-drop-link 450 170 \
    "$DMG_PATH" \
    "$APP_PATH"
else
  hdiutil create \
    -volname "TMRW W3 Browser" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"
fi

# Sign the DMG too
codesign \
  --sign "$APPLE_SIGNING_IDENTITY" \
  --timestamp \
  "$DMG_PATH"

echo ""
echo "==> Done!"
echo "    App:  $APP_PATH"
echo "    DMG:  $DMG_PATH"
echo ""
echo "    Distribute the DMG to testers via TestFlight or direct download."
echo "    For TestFlight: upload via Transporter app or xcrun altool."

rm -f "$ZIP_PATH"
