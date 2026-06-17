#!/usr/bin/env bash
# notarize.sh — package, codesign, notarize, and staple TMRW W3 Browser
#
# Prerequisites:
#   1. Xcode Command Line Tools (xcode-select --install)
#   2. "Developer ID Application" certificate installed in Keychain
#   3. .env file at repo root with all APPLE_* variables filled in
#   4. Run ./mach build && ./mach package first
#
# Usage:
#   ./scripts/notarize.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
SOURCE_DMG="$(ls "$OBJ_DIR/dist/"*.dmg 2>/dev/null | head -1)"
WORK_DIR="/tmp/tmrw-notarize"
APP_NAME="TMRW W3 Browser"
APP_PATH="$WORK_DIR/$APP_NAME.app"
ZIP_PATH="$WORK_DIR/$APP_NAME.zip"
OUT_DMG="$OBJ_DIR/dist/$APP_NAME.dmg"

# ── Load .env ──────────────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values."
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}"
    val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

# ── Validate ───────────────────────────────────────────────────────────────────
for var in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID APPLE_BUNDLE_ID APPLE_SIGNING_IDENTITY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

if [[ ! -f "$SOURCE_DMG" ]]; then
  echo "ERROR: Source DMG not found: $SOURCE_DMG"
  echo "Run './mach build && ./mach package' first."
  exit 1
fi

echo "==> Signer: $APPLE_SIGNING_IDENTITY"
echo "==> Bundle: $APPLE_BUNDLE_ID"
echo ""

# ── Step 1: Extract .app from mach package DMG ────────────────────────────────
echo "==> [1/6] Extracting app from packaged DMG..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

hdiutil attach "$SOURCE_DMG" -nobrowse -mountpoint /tmp/tmrw-src-dmg -quiet
cp -R "/tmp/tmrw-src-dmg/$APP_NAME.app" "$APP_PATH"
hdiutil detach /tmp/tmrw-src-dmg -quiet

echo "    Extracted to $APP_PATH"

echo "    Stripping extended attributes..."
xattr -cr "$APP_PATH"

# ── Step 2: Deep codesign with hardened runtime ───────────────────────────────
echo ""
echo "==> [2/6] Codesigning (deep, hardened runtime)..."

# Sign binaries that --deep misses because they live outside MacOS/Frameworks
SKIP_SIGN=(
  "$APP_PATH/Contents/Resources/gmp-clearkey/0.1/libclearkey.dylib"
  "$APP_PATH/Contents/Library/LaunchServices/org.mozilla.updater"
)
for bin in "${SKIP_SIGN[@]}"; do
  if [[ -f "$bin" ]]; then
    echo "    Pre-signing: $(basename "$bin")"
    codesign --force --timestamp --options runtime \
      --sign "$APPLE_SIGNING_IDENTITY" "$bin"
  fi
done

codesign \
  --deep \
  --force \
  --verify \
  --timestamp \
  --options runtime \
  --entitlements "$REPO_ROOT/browser/branding/w3ai/entitlements.plist" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_PATH"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP_PATH" && echo "    Signature OK"

# ── Step 3: Zip for notarization ──────────────────────────────────────────────
echo ""
echo "==> [3/6] Creating zip for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── Step 4: Submit to Apple Notary Service ────────────────────────────────────
echo ""
echo "==> [4/6] Submitting to Apple Notary Service (takes 1-5 min)..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --timeout 600

# ── Step 5: Staple ────────────────────────────────────────────────────────────
echo ""
echo "==> [5/6] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ── Step 6: Create signed DMG ─────────────────────────────────────────────────
echo ""
echo "==> [6/6] Creating distributable DMG..."
rm -f "$OUT_DMG"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$OUT_DMG"

codesign --sign "$APPLE_SIGNING_IDENTITY" --timestamp "$OUT_DMG"

echo ""
echo "============================================================"
echo "  Done!"
echo "  DMG: $OUT_DMG"
echo ""
echo "  Share this DMG with testers — it is fully notarized."
echo "  macOS will not show any security warning on install."
echo "============================================================"

rm -rf "$WORK_DIR"
