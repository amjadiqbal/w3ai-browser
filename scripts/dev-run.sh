#!/usr/bin/env bash
# dev-run.sh — launch the packaged build for development testing on macOS Tahoe
#
# Usage:
#   ./scripts/dev-run.sh                    # launch with dev profile
#   ./scripts/dev-run.sh -- -url google.com # pass extra args to firefox
#
# Prerequisites: ./mach build faster && ./mach package must be run first.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
PKG_APP="$OBJ/dist/firefox/TMRW.app"
RAW_APP="$OBJ/dist/TMRW.app"
FIREFOX="$PKG_APP/Contents/MacOS/firefox"
PROFILE="$OBJ/tmp/profile-default"

SIGNING_ID="Developer ID Application: Plato Technologies inc. (K9B6ZLA9M4)"
ENTITLEMENTS="$REPO_ROOT/browser/branding/w3ai/entitlements.plist"

if [[ ! -f "$FIREFOX" ]]; then
  echo "ERROR: Packaged app not found. Run: ./mach build faster && ./mach package"
  exit 1
fi

# Fix a .app bundle so it can run on macOS Tahoe with multi-process enabled.
# Applied to both the raw build (dist/TMRW.app, used by ./mach run) and
# the packaged build (dist/firefox/TMRW.app, used by this script).
#
# Three problems this resolves:
#  1. plugin-container.app sub-bundle missing → posix_spawnp Error:0 (child never spawns)
#  2. @executable_path/../MacOS rpath missing → dyld can't find XUL/libnss3
#  3. No JIT entitlement on plugin-container → SpiderMonkey exits immediately (status 1)
fix_app() {
  local APP="$1"
  local PC_BIN="$APP/Contents/Resources/plugin-container"
  local PC_BUNDLE="$APP/Contents/MacOS/plugin-container.app"
  [[ -f "$PC_BIN" ]] || return 0

  # Rpath fix (before signing — install_name_tool invalidates signatures)
  if ! otool -l "$PC_BIN" 2>/dev/null | grep -q "@executable_path/../MacOS"; then
    echo "==> [$APP_LABEL] Adding MacOS rpath to plugin-container..."
    install_name_tool -add_rpath "@executable_path/../MacOS" "$PC_BIN" 2>/dev/null || true
  fi

  # plugin-container.app sub-bundle (Firefox child process launcher expects this path)
  if [[ ! -e "$PC_BUNDLE/Contents/MacOS/plugin-container" ]]; then
    echo "==> [$APP_LABEL] Creating plugin-container.app sub-bundle..."
    rm -rf "$PC_BUNDLE"
    mkdir -p "$PC_BUNDLE/Contents/MacOS"
    ln -sf "../../../../Resources/plugin-container" "$PC_BUNDLE/Contents/MacOS/plugin-container"
    cat > "$PC_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>plugin-container</string>
  <key>CFBundleIdentifier</key><string>org.mozilla.plugincontainer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>151.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
  fi

  # Re-sign if ad-hoc or unsigned (happens after every fresh build/package)
  local CURRENT_SIG
  CURRENT_SIG=$(codesign -dv "$APP/Contents/MacOS/firefox" 2>&1 | grep "^Signature=" | head -1)
  if [[ "$CURRENT_SIG" == "Signature=adhoc" || -z "$CURRENT_SIG" ]]; then
    echo "==> [$APP_LABEL] Re-signing with Developer ID..."

    # Remove stray build-system file that blocks codesign
    rm -f "$APP/Contents/moz.build"

    # updater.app Info.plist (missing in artifact builds)
    local UPDATER_PLIST="$APP/Contents/MacOS/updater.app/Contents/Info.plist"
    if [[ ! -f "$UPDATER_PLIST" ]]; then
      mkdir -p "$(dirname "$UPDATER_PLIST")"
      cat > "$UPDATER_PLIST" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>org.mozilla.updater</string>
  <key>CFBundleIdentifier</key><string>org.mozilla.updater</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    fi

    xattr -cr "$APP"

    # Pre-sign binaries that --deep misses or that need special entitlements
    codesign --force --timestamp --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGNING_ID" \
      "$PC_BIN" 2>/dev/null

    for bin in \
      "$APP/Contents/Resources/gmp-clearkey/0.1/libclearkey.dylib" \
      "$APP/Contents/Library/LaunchServices/org.mozilla.updater"
    do
      [[ -f "$bin" ]] && codesign --force --timestamp --options runtime \
        --sign "$SIGNING_ID" "$bin" 2>/dev/null
    done

    # Deep-sign — errors about the plugin-container.app symlink are expected and suppressed
    codesign --force --deep --timestamp --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGNING_ID" \
      "$APP" 2>/dev/null
    echo "    Signed."
  fi
}

# Fix both the raw build (for ./mach run) and the packaged build (for this script)
APP_LABEL="raw"
fix_app "$RAW_APP" 2>/dev/null || true

APP_LABEL="pkg"
fix_app "$PKG_APP"

mkdir -p "$PROFILE"

echo "==> Launching TMRW (packaged build)..."
echo "    Profile: $PROFILE"
echo ""

exec "$FIREFOX" -foreground -profile "$PROFILE" "$@"
