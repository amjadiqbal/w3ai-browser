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
source "$REPO_ROOT/scripts/lib/ui.sh"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
SOURCE_DMG="$(ls -t "$OBJ_DIR/dist/tmrw-browser-"*.dmg 2>/dev/null | head -1)" || true
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

ui_info "Signer: $APPLE_SIGNING_IDENTITY"
ui_info "Bundle: $APPLE_BUNDLE_ID"
echo ""

# ── Step 1: Extract .app from mach package DMG ────────────────────────────────
ui_step 1 6 "Extracting app from packaged DMG"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

hdiutil attach "$SOURCE_DMG" -nobrowse -mountpoint /tmp/tmrw-src-dmg -quiet
cp -R "/tmp/tmrw-src-dmg/$APP_NAME.app" "$APP_PATH"
hdiutil detach /tmp/tmrw-src-dmg -quiet

ui_info "Extracted to $APP_PATH"

ui_spinner_start "Stripping extended attributes…"
xattr -cr "$APP_PATH"

# ── Step 1b: Patch updater.app Info.plist if missing ─────────────────────────
# The artifact build does not process Info.plist.in, so updater.app ships without
# Contents/Info.plist — codesign --deep fails on an invalid sub-bundle.
UPDATER_PLIST="$APP_PATH/Contents/MacOS/updater.app/Contents/Info.plist"
if [[ ! -f "$UPDATER_PLIST" ]]; then
  ui_info "Patching missing updater.app Info.plist…"
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
  ui_ok "Info.plist written"
fi

# ── Step 1b-extra: Inject plugin-container (artifact builds omit the .app bundle) ──
# Official Firefox ships plugin-container as Contents/MacOS/plugin-container.app/
# Artifact builds only provide a flat binary in dist/bin/; the package manifest
# skips it silently (MOZ_PKG_FATAL_WARNINGS is disabled for artifact builds).
# Without it, the content process never starts and all tabs stay blank.
PLUGIN_CONTAINER_SRC="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0/dist/bin/plugin-container"
if [[ -f "$PLUGIN_CONTAINER_SRC" ]]; then
  cp "$PLUGIN_CONTAINER_SRC" "$APP_PATH/Contents/Resources/plugin-container"
  chmod 755 "$APP_PATH/Contents/Resources/plugin-container"
  ui_ok "plugin-container injected"
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
  ui_ok "Custom updater binary installed"
fi

# ── Step 1d: Patch IsRecursivelyWritable → always return true ─────────────────
# Artifact builds do not compile our C++ changes to updaterfileutils_osx.mm.
# Binary-patch offset 0xeb10 (_IsRecursivelyWritable) to mov eax,1; ret so the
# updater never takes the XPC elevation path (we do not ship a privileged helper).
ui_spinner_start "Patching updater binary (fix XPC loop)…"
APP_PATH="$APP_PATH" REPO_ROOT="$REPO_ROOT" python3 - <<'PYEOF'
import os, sys
PATCH  = bytes([0xb8,0x01,0x00,0x00,0x00,0xc3,0x90,0x90,0x90,0x90])
OFFSET = 0xeb10
app    = os.environ['APP_PATH']
repo   = os.environ['REPO_ROOT']
obj    = repo + '/obj-x86_64-apple-darwin25.5.0'
targets = [
    app  + '/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater',
    app  + '/Contents/Library/LaunchServices/org.mozilla.updater',
    app  + '/Contents/Resources/org.mozilla.updater',
    obj  + '/dist/bin/org.mozilla.updater',
    obj  + '/dist/firefox/TMRW Browser.app/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater',
    obj  + '/dist/firefox/TMRW Browser.app/Contents/Library/LaunchServices/org.mozilla.updater',
    obj  + '/dist/firefox/TMRW Browser.app/Contents/Resources/org.mozilla.updater',
]
patched = 0
for path in targets:
    if not os.path.exists(path): continue
    with open(path, 'r+b') as f:
        f.seek(OFFSET)
        if f.read(2) == bytes([0xb8,0x01]): continue
        f.seek(OFFSET)
        f.write(PATCH)
        patched += 1
print(f'  Patched {patched} binaries')
PYEOF
ui_spinner_stop ok

# ── Step 2: Deep codesign with hardened runtime ───────────────────────────────
echo ""
ui_step 2 6 "Codesigning (deep, hardened runtime)"

# Sign binaries that --deep misses because they live outside MacOS/Frameworks,
# and plugin-container which must be explicitly signed before the bundle seal.
SKIP_SIGN=(
  "$APP_PATH/Contents/Resources/gmp-clearkey/0.1/libclearkey.dylib"
  "$APP_PATH/Contents/Library/LaunchServices/org.mozilla.updater"
  "$APP_PATH/Contents/Resources/plugin-container"
)
for bin in "${SKIP_SIGN[@]}"; do
  if [[ -f "$bin" ]]; then
    ui_info "Pre-signing: $(basename "$bin")"
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

ui_spinner_start "Verifying signature…"
codesign --verify --deep --strict "$APP_PATH" && ui_spinner_stop ok

# ── Step 3: Zip for notarization ──────────────────────────────────────────────
echo ""
ui_step 3 6 "Creating zip for notarization"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── Step 4: Submit to Apple Notary Service ────────────────────────────────────
echo ""
ui_step 4 6 "Submitting to Apple Notary Service (1–5 min)"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --timeout 600

# ── Step 5: Staple ────────────────────────────────────────────────────────────
echo ""
ui_step 5 6 "Stapling notarization ticket"
STAPLE_OK=0
for attempt in 1 2 3; do
  if xcrun stapler staple "$APP_PATH" 2>&1; then
    STAPLE_OK=1
    break
  fi
  ui_warn "Staple attempt $attempt failed (CloudKit propagation delay). Retrying in 30s..."
  sleep 30
done
if [[ $STAPLE_OK -eq 0 ]]; then
  ui_warn "Stapling failed after 3 attempts. App is still notarized — Gatekeeper will verify online."
fi

# ── Step 6: Create signed installer DMG with branded layout ───────────────────
echo ""
ui_step 6 6 "Creating distributable DMG"
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

printf "\n${UI_BOLD}${UI_GREEN}  Notarization complete!${UI_RESET}\n\n"
ui_ok "DMG: $OUT_DMG"
printf "  ${UI_DIM}Share this DMG — fully notarized, no security warnings on install.${UI_RESET}\n\n"

rm -rf "$WORK_DIR"
