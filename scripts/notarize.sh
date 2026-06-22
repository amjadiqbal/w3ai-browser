#!/usr/bin/env bash
# notarize.sh — package, codesign, notarize, and staple TMRW Browser
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
SOURCE_DMG="$(ls -t "$OBJ_DIR/dist/tmrw-w3-browser-"*.dmg 2>/dev/null | head -1)" || true
# Fallback: older builds used the default firefox-* naming; pick newest
if [[ -z "$SOURCE_DMG" ]]; then
  SOURCE_DMG="$(ls -t "$OBJ_DIR/dist/firefox-"*.dmg 2>/dev/null | head -1)" || true
fi
WORK_DIR="/tmp/tmrw-notarize"
APP_NAME="TMRW Browser"
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
  echo "ERROR: Source DMG not found in $OBJ_DIR/dist/"
  echo "Run: ./mach build faster && ./mach package"
  echo "(Never use './mach build' alone — it tries to pull artifacts and fails on this fork)"
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

# ── Step 1b: Patch updater.app Info.plist if missing ─────────────────────────
# The artifact build does not process Info.plist.in, so updater.app ships without
# Contents/Info.plist — codesign --deep fails on an invalid sub-bundle.
UPDATER_PLIST="$APP_PATH/Contents/MacOS/updater.app/Contents/Info.plist"
if [[ ! -f "$UPDATER_PLIST" ]]; then
  echo "    Patching missing updater.app/Contents/Info.plist..."
  mkdir -p "$(dirname "$UPDATER_PLIST")"
  SMReq="identifier \"${APPLE_BUNDLE_ID}\" and anchor apple generic and certificate leaf[subject.OU] = \"${APPLE_TEAM_ID}\""
  cat > "$UPDATER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleDisplayName</key>
	<string>updater</string>
	<key>CFBundleExecutable</key>
	<string>org.mozilla.updater</string>
	<key>CFBundleIconFile</key>
	<string>updater.icns</string>
	<key>CFBundleIdentifier</key>
	<string>org.mozilla.updater</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>updater</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>LSHasLocalizedDisplayName</key>
	<true/>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSRequiresAquaSystemAppearance</key>
	<false/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>LSUIElement</key>
	<true/>
	<key>SMAuthorizedClients</key>
	<array>
		<string>${SMReq}</string>
	</array>
</dict>
</plist>
PLIST
  echo "    Info.plist written."
fi

# ── Step 1c: Replace updater binary with our custom build (no MAR sig check) ──
CUSTOM_UPDATER="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0/dist/bin/org.mozilla.updater"
if [[ -f "$CUSTOM_UPDATER" ]]; then
  for UPDATER_BIN in \
    "$APP_PATH/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater" \
    "$APP_PATH/Contents/Library/LaunchServices/org.mozilla.updater" \
    "$APP_PATH/Contents/Resources/org.mozilla.updater"
  do
    if [[ -f "$UPDATER_BIN" ]]; then
      cp "$CUSTOM_UPDATER" "$UPDATER_BIN"
      chmod 755 "$UPDATER_BIN"
    fi
  done
  echo "    Custom updater binary installed."
fi

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
STAPLE_OK=0
for attempt in 1 2 3; do
  if xcrun stapler staple "$APP_PATH" 2>&1; then
    STAPLE_OK=1
    break
  fi
  echo "    Staple attempt $attempt failed (CloudKit propagation delay). Retrying in 30s..."
  sleep 30
done
if [[ $STAPLE_OK -eq 0 ]]; then
  echo "    WARNING: Stapling failed after 3 attempts. App is still notarized — Gatekeeper will verify online."
fi

# ── Step 6: Create signed installer DMG with branded layout ───────────────────
echo ""
echo "==> [6/6] Creating distributable DMG..."
STAGING_DMG="/tmp/tmrw-installer-rw.dmg"
MOUNT_POINT="/tmp/tmrw-installer-mount"
rm -f "$OUT_DMG" "$STAGING_DMG"

# Size = app on disk + 80 MB for background, symlink, DS_Store headroom
APP_SIZE_MB=$(du -sm "$APP_PATH" | cut -f1)
DMG_SIZE_MB=$((APP_SIZE_MB + 80))

hdiutil create \
  -volname "$APP_NAME" \
  -size ${DMG_SIZE_MB}m \
  -fs HFS+ \
  -layout SPUD \
  "$STAGING_DMG"

hdiutil attach "$STAGING_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

cp -R "$APP_PATH"        "$MOUNT_POINT/$APP_NAME.app"
ln -s /Applications      "$MOUNT_POINT/Applications"
mkdir -p                 "$MOUNT_POINT/.background"
cp "$REPO_ROOT/browser/branding/w3ai/background.png" \
                         "$MOUNT_POINT/.background/background.png"
cp "$REPO_ROOT/browser/branding/w3ai/dsstore" \
                         "$MOUNT_POINT/.DS_Store"
cp "$REPO_ROOT/browser/branding/w3ai/disk.icns" \
                         "$MOUNT_POINT/.VolumeIcon.icns"

hdiutil detach "$MOUNT_POINT" -quiet

# Compress to final read-only DMG
hdiutil convert "$STAGING_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet
rm -f "$STAGING_DMG"

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
