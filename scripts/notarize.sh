#!/usr/bin/env bash
# notarize.sh — package, codesign, notarize, and staple TMRW
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
APP_NAME="TMRW"
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

# Detect App Store mode — "Apple Distribution" certs go through Transporter, not notarytool
IS_APP_STORE=false
[[ "${APPLE_SIGNING_IDENTITY:-}" == *"Apple Distribution"* ]] && IS_APP_STORE=true

# ── Validate ───────────────────────────────────────────────────────────────────
for var in APPLE_BUNDLE_ID APPLE_SIGNING_IDENTITY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done
if ! $IS_APP_STORE; then
  for var in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
    if [[ -z "${!var:-}" ]]; then
      echo "ERROR: $var is not set in .env (required for Developer ID notarization)"
      exit 1
    fi
  done
fi

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

hdiutil detach /tmp/tmrw-src-dmg -force -quiet 2>/dev/null || true
hdiutil attach "$SOURCE_DMG" -nobrowse -mountpoint /tmp/tmrw-src-dmg -quiet
SRC_APP=$(find /tmp/tmrw-src-dmg -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$SRC_APP" ]]; then
  ui_fail "No .app bundle found in source DMG"
  hdiutil detach /tmp/tmrw-src-dmg -quiet 2>/dev/null || true
  exit 1
fi
cp -R "$SRC_APP" "$APP_PATH"
hdiutil detach /tmp/tmrw-src-dmg -quiet

ui_info "Extracted to $APP_PATH"

ui_spinner_start "Stripping extended attributes…"
xattr -cr "$APP_PATH"
ui_spinner_stop ok

# ── Step 1a: Inject TMRW branding into omni.ja ────────────────────────────────
# The source DMG was produced by mach package which packs Mozilla's locale files.
# Patch omni.ja in-place to replace/add brand.ftl with TMRW brand strings.
BRAND_FTL="$REPO_ROOT/browser/branding/w3ai/locales/en-US/brand.ftl"
if [[ -f "$BRAND_FTL" ]]; then
  ui_info "Injecting TMRW brand.ftl into omni.ja…"
  OMNI_JA="$APP_PATH/Contents/Resources/omni.ja"
  if [[ -f "$OMNI_JA" ]]; then
    python3 - "$OMNI_JA" "$BRAND_FTL" <<'PYEOF'
import io, sys, zipfile
omni_path, brand_path = sys.argv[1], sys.argv[2]
brand_data = open(brand_path, 'rb').read()
buf = io.BytesIO()
replaced = False
with zipfile.ZipFile(omni_path, 'r') as zin:
    with zipfile.ZipFile(buf, 'w') as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == 'localization/en-US/branding/brand.ftl':
                data = brand_data
                replaced = True
            zout.writestr(item, data, compress_type=item.compress_type)
        if not replaced:
            zi = zipfile.ZipInfo('localization/en-US/branding/brand.ftl')
            zi.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(zi, brand_data)
with open(omni_path, 'wb') as f:
    f.write(buf.getvalue())
print(f'  {"Replaced" if replaced else "Added"} brand.ftl in omni.ja')
PYEOF
  fi
  # Also replace loose brand.ftl (belt-and-suspenders)
  LOOSE_BRAND="$APP_PATH/Contents/Resources/browser/localization/en-US/branding/brand.ftl"
  if [[ -f "$LOOSE_BRAND" ]]; then
    cp "$BRAND_FTL" "$LOOSE_BRAND"
    ui_info "Replaced loose brand.ftl"
  fi
  # Replace Assets.car with TMRW icon set
  ASSETS_CAR="$REPO_ROOT/browser/branding/w3ai/Assets.car"
  if [[ -f "$ASSETS_CAR" ]]; then
    cp "$ASSETS_CAR" "$APP_PATH/Contents/Resources/Assets.car"
    ui_info "Replaced Assets.car with TMRW icons"
  fi
  # Replace firefox.icns and document.icns
  for ICON in firefox.icns document.icns; do
    SRC="$REPO_ROOT/browser/branding/w3ai/$ICON"
    DST="$APP_PATH/Contents/Resources/$ICON"
    [[ -f "$SRC" && -f "$DST" ]] && cp "$SRC" "$DST"
  done
  # Update Info.plist — CFBundleName, CFBundleDisplayName, CFBundleIdentifier
  /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APPLE_BUNDLE_ID}" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  ui_info "Patched CFBundleIdentifier → ${APPLE_BUNDLE_ID}"
  _VER="${APP_VERSION:-1.0.1}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${_VER}" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${_VER}" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  ui_info "Patched version → ${_VER}"
  # Patch application.ini — the runtime version string read by the About dialog
  _APP_INI="$APP_PATH/Contents/Resources/application.ini"
  if [[ -f "$_APP_INI" ]]; then
    sed -i '' "s/^Version=.*/Version=${_VER}/" "$_APP_INI"
    sed -i '' "s/^BuildID=.*/BuildID=$(date -u +%Y%m%d%H%M%S)/" "$_APP_INI"
    if $IS_APP_STORE; then
      # App Store delivers all updates; clear the external MAR update URL
      sed -i '' '/^\[AppUpdate\]/,/^\[/{/^URL=/s/.*/URL=/;}' "$_APP_INI"
    fi
    ui_info "Patched application.ini → Version ${_VER}"
  fi
  if $IS_APP_STORE; then
    # Patch browser/omni.ja: disable external update checker for App Store builds.
    # App Store delivers all updates; the in-app MAR updater must not run.
    _BROWSER_OMNI="$APP_PATH/Contents/Resources/browser/omni.ja"
    if [[ -f "$_BROWSER_OMNI" ]]; then
      python3 - "$_BROWSER_OMNI" <<'PYEOF'
import io, sys, zipfile, re
omni_path = sys.argv[1]
buf = io.BytesIO()
with zipfile.ZipFile(omni_path, 'r') as zin:
    with zipfile.ZipFile(buf, 'w') as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == 'defaults/preferences/firefox-branding.js':
                text = data.decode('utf-8', errors='replace')
                text = text.replace(
                    'pref("app.update.enabled", true)',
                    'pref("app.update.enabled", false, locked)'
                )
                text = text.replace(
                    'pref("app.update.auto", false)',
                    'pref("app.update.auto", false, locked)'
                )
                text = re.sub(
                    r'pref\("app\.update\.url",\s*"[^"]*"\)',
                    'pref("app.update.url", "")',
                    text
                )
                data = text.encode('utf-8')
                print('  Disabled app.update in firefox-branding.js for App Store')
            zout.writestr(item, data, compress_type=item.compress_type)
with open(omni_path, 'wb') as f:
    f.write(buf.getvalue())
PYEOF
      ui_info "Patched browser/omni.ja: app.update disabled (App Store mode)"
    fi
  fi
  # Declare export compliance — bypasses App Store Connect encryption questionnaire.
  # TMRW Browser uses standard publicly-available TLS/SSL (Firefox NSS library)
  # which qualifies for US EAR Section 740.17(b) exemption; no ERN required.
  /usr/libexec/PlistBuddy -c "Set :ITSAppUsesNonExemptEncryption NO" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool NO" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  ui_info "Patched ITSAppUsesNonExemptEncryption → NO (export compliance)"
  # Update en.lproj/InfoPlist.strings — macOS menu bar reads this over Info.plist
  _STRINGS="$APP_PATH/Contents/Resources/en.lproj/InfoPlist.strings"
  if [[ -f "$_STRINGS" ]]; then
    plutil -convert xml1 "$_STRINGS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW" "$_STRINGS" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string TMRW" "$_STRINGS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW" "$_STRINGS" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW" "$_STRINGS" 2>/dev/null || true
    plutil -convert binary1 "$_STRINGS" 2>/dev/null || true
    ui_info "Patched InfoPlist.strings → TMRW"
  fi
fi

# ── Step 1a-extra: Add LSHandlerRank to CFBundleDocumentTypes ────────────────
# Apple requires every CFBundleDocumentTypes entry to have LSHandlerRank.
# Firefox ships without it on most entries — Transporter rejects them (error 90788).
python3 - "$APP_PATH/Contents/Info.plist" <<'PYEOF'
import sys, plistlib
path = sys.argv[1]
with open(path, 'rb') as f:
    p = plistlib.load(f)
changed = 0
for entry in p.get('CFBundleDocumentTypes', []):
    if 'LSHandlerRank' not in entry:
        entry['LSHandlerRank'] = 'Alternate'
        changed += 1
if changed:
    with open(path, 'wb') as f:
        plistlib.dump(p, f, fmt=plistlib.FMT_XML)
    print(f'  Added LSHandlerRank=Alternate to {changed} document type entries')
PYEOF


# ── Step 1a-extra1b: Merge arm64 slice → universal binaries (fixes 91167) ────
# Mozilla's current macOS nightly DMG is a universal fat binary (x86_64 + arm64).
# We download it once and extract the arm64 slice into our x86_64 artifact using lipo,
# satisfying App Store requirement 91167 ("bundle must include arm64-capable binary").
# The cache at obj-arm64-cache/ persists between builds; delete it to force re-download.
_ARM64_DMG_CACHE="$REPO_ROOT/obj-arm64-cache/firefox-nightly-mac-universal.dmg"
_ARM64_URL="https://archive.mozilla.org/pub/firefox/nightly/latest-mozilla-central/firefox-154.0a1.en-US.mac.dmg"

if [[ ! -f "$_ARM64_DMG_CACHE" ]]; then
  mkdir -p "$(dirname "$_ARM64_DMG_CACHE")"
  ui_info "Downloading Firefox universal DMG (~170 MB) for arm64 slice…"
  curl -L -o "$_ARM64_DMG_CACHE" "$_ARM64_URL" --progress-bar 2>&1 || true
fi

if [[ -f "$_ARM64_DMG_CACHE" ]]; then
  ui_info "Merging arm64 slice into x86_64 binaries → universal…"
  _ARM64_MNT="/tmp/tmrw-arm64-universal"
  hdiutil detach "$_ARM64_MNT" -force -quiet 2>/dev/null || true
  hdiutil attach "$_ARM64_DMG_CACHE" -nobrowse -mountpoint "$_ARM64_MNT" -quiet

  _ARM64_SRC=$(find "$_ARM64_MNT" -maxdepth 1 -name "*.app" -type d | head -1)

  if [[ -n "$_ARM64_SRC" ]]; then
    _lipoed=0

    # Phase A: path-matched binaries (same relative path in both .app bundles)
    while IFS= read -r -d '' _x86_f; do
      file "$_x86_f" 2>/dev/null | grep -q "Mach-O" || continue
      _rel="${_x86_f#$APP_PATH/}"
      _arm_f="$_ARM64_SRC/$_rel"
      [[ -f "$_arm_f" ]] || continue
      file "$_arm_f" 2>/dev/null | grep -q "Mach-O" || continue
      _tmp="$(mktemp /tmp/arm64-slice.XXXXXX)"
      if lipo -extract arm64 "$_arm_f" -output "$_tmp" 2>/dev/null; then
        if lipo -create "$_x86_f" "$_tmp" -output "$_x86_f.fat" 2>/dev/null; then
          mv "$_x86_f.fat" "$_x86_f"
          _lipoed=$((_lipoed + 1))
        fi
      fi
      rm -f "$_tmp"
    done < <(find "$APP_PATH" -type f -print0)

    # Phase B: nested .app executables whose filenames changed between Firefox versions.
    # Match by .app directory name; read CFBundleExecutable from each Info.plist.
    while IFS= read -r _nested; do
      [[ "$_nested" == "$APP_PATH" ]] && continue
      _dir=$(basename "$_nested")
      _arm_nested="$_ARM64_SRC/Contents/MacOS/$_dir"
      [[ -d "$_arm_nested" ]] || continue
      _our_exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
        "$_nested/Contents/Info.plist" 2>/dev/null) || continue
      _arm_exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
        "$_arm_nested/Contents/Info.plist" 2>/dev/null) || continue
      _our_bin="$_nested/Contents/MacOS/$_our_exe"
      _arm_bin="$_arm_nested/Contents/MacOS/$_arm_exe"
      [[ -f "$_our_bin" && -f "$_arm_bin" ]] || continue
      lipo -info "$_our_bin" 2>/dev/null | grep -q "arm64" && continue
      _tmp="$(mktemp /tmp/arm64-slice.XXXXXX)"
      if lipo -extract arm64 "$_arm_bin" -output "$_tmp" 2>/dev/null; then
        if lipo -create "$_our_bin" "$_tmp" -output "$_our_bin.fat" 2>/dev/null; then
          mv "$_our_bin.fat" "$_our_bin"
          _lipoed=$((_lipoed + 1))
          ui_info "  Universal helper: $_dir"
        fi
      fi
      rm -f "$_tmp"
    done < <(find "$APP_PATH/Contents" -name "*.app" -type d | sort)

    ui_ok "Universal: $_lipoed binaries now contain x86_64 + arm64 slices"
  fi

  hdiutil detach "$_ARM64_MNT" -quiet 2>/dev/null || true
fi

# ── Step 1a-extra1c: Remove orphaned duplicate executables from helpers ────────
# The x86_64 artifact ships both "Nightly X" and "W3Ai X" executables in some
# helpers (gpu-helper, media-plugin-helper, security-module-helper). Only the
# binary named by CFBundleExecutable is valid; the extras cause Apple 90885.
_removed_dupes=0
for _H in "$APP_PATH/Contents/MacOS/"*.app; do
  [[ -d "$_H" ]] || continue
  _HP="$_H/Contents/Info.plist"
  [[ -f "$_HP" ]] || continue
  _canon=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$_HP" 2>/dev/null) || continue
  [[ -z "$_canon" ]] && continue
  _macosdir="$_H/Contents/MacOS"
  [[ -d "$_macosdir" ]] || continue
  while IFS= read -r _exe; do
    [[ "$(basename "$_exe")" == "$_canon" ]] && continue
    file "$_exe" 2>/dev/null | grep -q "Mach-O" || continue
    ui_info "  Removing orphan: $(basename "$_H")/$(basename "$_exe")"
    rm -f "$_exe"
    _removed_dupes=$((_removed_dupes + 1))
  done < <(find "$_macosdir" -maxdepth 1 -type f)
done
[[ $_removed_dupes -gt 0 ]] && ui_ok "Removed $_removed_dupes orphaned duplicate executable(s)" || ui_info "No duplicate executables found"

# ── Step 1a-extra2: Fix flat frameworks → proper versioned structure ──────────
# Artifact builds produce flat .framework bundles (binary + Resources directly in root).
# Apple requires the versioned layout: Versions/A/<binary>, Versions/Current -> A,
# <name> -> Versions/Current/<name>, Resources -> Versions/Current/Resources.
# Transporter rejects flat frameworks with errors 90291 and 90292.
fix_flat_framework() {
  local fw="$1"
  local name
  name="$(basename "$fw" .framework)"
  [[ -d "$fw/Versions" ]] && return 0   # already versioned
  ui_info "Restructuring flat framework: $name.framework"
  mkdir -p "$fw/Versions/A"
  # Move binary
  if [[ -f "$fw/$name" ]] && [[ ! -L "$fw/$name" ]]; then
    mv "$fw/$name" "$fw/Versions/A/$name"
  fi
  # Move Resources directory
  if [[ -d "$fw/Resources" ]] && [[ ! -L "$fw/Resources" ]]; then
    mv "$fw/Resources" "$fw/Versions/A/Resources"
  fi
  # Create required symlinks
  ln -s "A"                           "$fw/Versions/Current"
  ln -s "Versions/Current/$name"      "$fw/$name"
  ln -s "Versions/Current/Resources"  "$fw/Resources"
}

for FW in \
  "$APP_PATH/Contents/Frameworks/ChannelPrefs.framework" \
  "$APP_PATH/Contents/MacOS/updater.app/Contents/Frameworks/UpdateSettings.framework"
do
  [[ -d "$FW" ]] && fix_flat_framework "$FW"
done

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
    obj  + '/dist/firefox/TMRW.app/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater',
    obj  + '/dist/firefox/TMRW.app/Contents/Library/LaunchServices/org.mozilla.updater',
    obj  + '/dist/firefox/TMRW.app/Contents/Resources/org.mozilla.updater',
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

# ── Step 1d-extra: Rename updater binary to TMRW branding ────────────────────
# The artifact ships the updater executable as "org.mozilla.updater" — a Mozilla
# identifier that must be replaced with our TMRW branding before App Store review.
# Rename the binary inside updater.app and update CFBundleExecutable to match.
_UPDATER_APP="$APP_PATH/Contents/MacOS/updater.app"
_OLD_BIN="$_UPDATER_APP/Contents/MacOS/org.mozilla.updater"
_NEW_BIN="$_UPDATER_APP/Contents/MacOS/tmrw.updater"
if [[ -f "$_OLD_BIN" ]]; then
  mv "$_OLD_BIN" "$_NEW_BIN"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable tmrw.updater" \
    "$_UPDATER_APP/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string tmrw.updater" \
    "$_UPDATER_APP/Contents/Info.plist" 2>/dev/null || true
  ui_ok "Updater binary renamed → tmrw.updater"
fi

# ── Step 1d-extra2: Rename main executable firefox → TMRW ────────────────────
# Must run AFTER lipo (arm64 merge) so the universal binary exists under its
# original name before the rename. The signing exclusion for "TMRW" in step [2a]
# is already in place; the main binary is sealed via the main bundle in step [2c].
_MAIN_OLD="$APP_PATH/Contents/MacOS/firefox"
_MAIN_NEW="$APP_PATH/Contents/MacOS/TMRW"
if [[ -f "$_MAIN_OLD" && ! -f "$_MAIN_NEW" ]]; then
  mv "$_MAIN_OLD" "$_MAIN_NEW"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable TMRW" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  ui_ok "Main binary renamed: firefox → TMRW"
fi

# ── Step 1e: Embed provisioning profile (App Store mode only) ────────────────
FOUND_PROFILE=""  # initialised here; step 2b reuses it for nested helper embedding
if $IS_APP_STORE; then
  ui_info "App Store mode — embedding provisioning profile"

  # Use explicit path from .env first, then fall back to searching known dirs
  FOUND_PROFILE="${APPLE_PROVISIONING_PROFILE:-}"
  # Expand ~ if present
  FOUND_PROFILE="${FOUND_PROFILE/#\~/$HOME}"

  if [[ -z "$FOUND_PROFILE" || ! -f "$FOUND_PROFILE" ]]; then
    # Search Xcode-managed profile directories as fallback
    FOUND_PROFILE=""
    for dir in \
      "$HOME/Library/MobileDevice/Provisioning Profiles" \
      "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
      "$HOME/Downloads"
    do
      [[ -d "$dir" ]] || continue
      while IFS= read -r -d '' pf; do
        platform_check=$(openssl smime -inform DER -verify -noverify -in "$pf" 2>/dev/null \
          | grep -c "OSX\|macOS" || true)
        [[ "$platform_check" -gt 0 ]] && { FOUND_PROFILE="$pf"; break 2; }
      done < <(find "$dir" \( -name "*.mobileprovision" -o -name "*.provisionprofile" \) -print0 2>/dev/null)
    done
  fi

  if [[ -z "${FOUND_PROFILE:-}" || ! -f "$FOUND_PROFILE" ]]; then
    echo ""
    ui_fail "Provisioning profile not found."
    echo ""
    echo "  Set APPLE_PROVISIONING_PROFILE in .env to the full path of your"
    echo "  Mac App Store distribution profile (.provisionprofile), e.g.:"
    echo "    APPLE_PROVISIONING_PROFILE=/Users/$(whoami)/Downloads/TMRW_Mac_Distribution_Profile.provisionprofile"
    echo ""
    echo "  Download it from:"
    echo "  1. https://developer.apple.com/account/resources/profiles/add"
    echo "  2. Distribution → Mac App Store → Mac App Distribution"
    echo "  3. Bundle ID: $APPLE_BUNDLE_ID"
    echo "  4. Certificate: Apple Distribution: Plato Technologies inc. (K9B6ZLA9M4)"
    echo ""
    exit 1
  fi

  cp "$FOUND_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
  xattr -c "$APP_PATH/Contents/embedded.provisionprofile" 2>/dev/null || true
  ui_ok "Embedded profile: $(basename "$FOUND_PROFILE")"
fi

# ── Step 2: Codesign with hardened runtime + App Sandbox ─────────────────────
echo ""
ui_step 2 6 "Codesigning (hardened runtime, App Sandbox)"

MAIN_ENT="$REPO_ROOT/browser/branding/w3ai/entitlements.plist"
HELP_ENT="$REPO_ROOT/browser/branding/w3ai/entitlements-helper.plist"
# Used for nested .app bundles in non-App Store (Developer ID) mode only.
NESTED_ENT="$REPO_ROOT/browser/branding/w3ai/entitlements-nested-app.plist"

# App Store: add application-identifier + team-identifier to the main bundle entitlements.
# Nested helpers receive the same application-identifier via a dynamically-generated
# entitlements file in step [2b], along with the embedded provisioning profile.
if $IS_APP_STORE; then
  APP_STORE_ENT="$(mktemp /tmp/entitlements-appstore.XXXXXX)"
  cp "$MAIN_ENT" "$APP_STORE_ENT"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string ${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}" \
    "$APP_STORE_ENT" 2>/dev/null || \
  /usr/libexec/PlistBuddy \
    -c "Set :com.apple.application-identifier ${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}" \
    "$APP_STORE_ENT" 2>/dev/null || true
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.developer.team-identifier string ${APPLE_TEAM_ID}" \
    "$APP_STORE_ENT" 2>/dev/null || \
  /usr/libexec/PlistBuddy \
    -c "Set :com.apple.developer.team-identifier ${APPLE_TEAM_ID}" \
    "$APP_STORE_ENT" 2>/dev/null || true
  MAIN_ENT="$APP_STORE_ENT"
  ui_info "Entitlements: application-identifier=${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}"
fi

# [2a] Sign all dylibs, binaries, and frameworks with helper entitlements.
# Covers gmp-clearkey, XUL (the Mozilla engine), plugin-container, updater,
# and all .framework bundles in Contents/Frameworks/.
ui_info "Signing dylibs and standalone binaries…"
while IFS= read -r -d '' f; do
  codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$HELP_ENT" "$f" 2>/dev/null || true
done < <(find \
  "$APP_PATH/Contents/Resources" \
  "$APP_PATH/Contents/Library" \
  -type f \( -name "*.dylib" -o -name "*.so" -o -name "plugin-container" -o -name "org.mozilla.updater" \) \
  -print0 2>/dev/null)

# Sign framework bundles in Contents/Frameworks/ (ChannelPrefs.framework etc.)
ui_info "Signing frameworks…"
while IFS= read -r fw; do
  ui_info "  $(basename "$fw")"
  codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$HELP_ENT" "$fw"
done < <(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -maxdepth 1 2>/dev/null)

# Sign extension-less Mach-O files directly in Contents/MacOS/ (e.g. XUL)
while IFS= read -r -d '' f; do
  codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$HELP_ENT" "$f" 2>/dev/null || true
done < <(find "$APP_PATH/Contents/MacOS" -maxdepth 1 \
  -not -name "*.app" -not -name "TMRW" -not -name "firefox" \
  -type f -print0 2>/dev/null)

# [2b] Sign every nested .app bundle.
# App Store: helpers MUST have app-sandbox=true (Transporter 409).
# Other helpers: only sandbox + JIT flags, NO application-identifier (avoids 90885).
# plugin-container is special: it needs com.tmrw.w3ai identity so macOS puts it in the
# same sandbox container as the main app. Without this, plugin-container runs in an
# org.mozilla.plugincontainer container that has no provisioning profile → macOS kills
# it immediately in TestFlight → all content processes die → remoteTab is always null.
# The fix: change its CFBundleIdentifier to com.tmrw.w3ai and add application-identifier
# matching the main app. No separate embedded.provisionprofile needed — the main app's
# profile covers K9B6ZLA9M4.com.tmrw.w3ai and Transporter validates the helper against it.
if $IS_APP_STORE; then
  _PC_APP="$APP_PATH/Contents/MacOS/plugin-container.app"
  if [[ -d "$_PC_APP" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APPLE_BUNDLE_ID}" \
      "$_PC_APP/Contents/Info.plist" 2>/dev/null || true
    ui_info "plugin-container.app → CFBundleIdentifier: ${APPLE_BUNDLE_ID} (shared sandbox container)"
  fi
fi

ui_info "Signing nested helper apps…"
if $IS_APP_STORE; then
  _NESTED_AS_ENT="$(mktemp /tmp/entitlements-nested-appstore.XXXXXX)"
  cat > "$_NESTED_AS_ENT" <<ENTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENTXML

  # plugin-container: application-identifier = com.tmrw.w3ai so macOS assigns it to
  # the same sandbox container as the main app. The main app's embedded.provisionprofile
  # covers K9B6ZLA9M4.com.tmrw.w3ai — no separate profile needed in the helper.
  # network.client + network.server allow the content process to load web pages.
  _PC_ENT="$(mktemp /tmp/entitlements-plugin-container.XXXXXX)"
  cat > "$_PC_ENT" <<ENTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}</string>
  <key>com.apple.developer.team-identifier</key><string>${APPLE_TEAM_ID}</string>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.network.server</key><true/>
</dict>
</plist>
ENTXML

  while IFS= read -r nested; do
    [[ "$nested" == "$APP_PATH" ]] && continue
    ui_info "  $(echo "$nested" | sed "s|$APP_PATH/||")"
    if [[ "$(basename "$nested")" == "plugin-container.app" ]]; then
      codesign --deep --force --timestamp --options runtime \
        --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$_PC_ENT" "$nested"
    else
      codesign --deep --force --timestamp --options runtime \
        --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$_NESTED_AS_ENT" "$nested"
    fi
  done < <(find "$APP_PATH/Contents" -name "*.app" -type d | sort -r)

  rm -f "$_NESTED_AS_ENT" "$_PC_ENT"
else
  while IFS= read -r nested; do
    [[ "$nested" == "$APP_PATH" ]] && continue
    ui_info "  $(echo "$nested" | sed "s|$APP_PATH/||")"
    codesign --deep --force --timestamp --options runtime \
      --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$NESTED_ENT" "$nested"
  done < <(find "$APP_PATH/Contents" -name "*.app" -type d | sort -r)
fi

# [2c] Seal the main bundle WITHOUT --deep (all nested code already signed above).
# Applying --deep here would override the nested apps with MAIN_ENT, reintroducing 90885.
ui_info "Sealing main app bundle…"
codesign \
  --force \
  --verify \
  --timestamp \
  --options runtime \
  --entitlements "$MAIN_ENT" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_PATH"

ui_spinner_start "Verifying signature…"
codesign --verify --deep --strict "$APP_PATH" && ui_spinner_stop ok

# Steps 3-5 (notarize + staple) are only for Developer ID / direct distribution.
# App Store apps skip notarytool — Transporter handles validation instead.
if $IS_APP_STORE; then
  ui_step 3 6 "App Store mode — skipping notarization (use Transporter)"
  ui_step 4 6 "Skipped"
  ui_step 5 6 "Skipped"
else
  # ── Step 3: Zip for notarization ────────────────────────────────────────────
  echo ""
  ui_step 3 6 "Creating zip for notarization"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  # ── Step 4: Submit to Apple Notary Service ──────────────────────────────────
  echo ""
  ui_step 4 6 "Submitting to Apple Notary Service (1–5 min)"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --timeout 600

  # ── Step 5: Staple ──────────────────────────────────────────────────────────
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

echo ""
if $IS_APP_STORE; then
  printf "${UI_BOLD}${UI_GREEN}  App Store build complete!${UI_RESET}\n\n"
  ui_ok "DMG (intermediate): $OUT_DMG"
  printf "  ${UI_DIM}Run ./scripts/build-pkg.sh to package as .pkg for Transporter submission.${UI_RESET}\n\n"
else
  printf "${UI_BOLD}${UI_GREEN}  Notarization complete!${UI_RESET}\n\n"
  ui_ok "DMG: $OUT_DMG"
  printf "  ${UI_DIM}Share this DMG — fully notarized, no security warnings on install.${UI_RESET}\n\n"
fi

rm -rf "$WORK_DIR"
