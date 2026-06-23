#!/usr/bin/env bash
# dev-run.sh — launch the packaged build for development testing on macOS Tahoe
#
# Use this instead of ./mach run on macOS 26 (Tahoe).
# The standard ./mach run uses dist/TMRW Browser.app which has absolute symlinks
# that prevent valid code signing — macOS Tahoe then kills all child processes.
# The packaged build (dist/firefox/) has real files, valid signing, and works.
#
# Usage:
#   ./scripts/dev-run.sh                    # launch with dev profile
#   ./scripts/dev-run.sh -- -url google.com # pass extra args to firefox
#
# Prerequisites: ./mach build faster && ./mach package must be run first.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
PKG_APP="$OBJ/dist/firefox/TMRW Browser.app"
FIREFOX="$PKG_APP/Contents/MacOS/firefox"
PROFILE="$OBJ/tmp/profile-default"

SIGNING_ID="Developer ID Application: Plato Technologies inc. (K9B6ZLA9M4)"

if [[ ! -f "$FIREFOX" ]]; then
  echo "ERROR: Packaged app not found. Run: ./mach build faster && ./mach package"
  exit 1
fi

# Sign the packaged app if it has an ad-hoc signature (happens after fresh package)
CURRENT_SIG=$(codesign -dv "$FIREFOX" 2>&1 | grep "^Signature=" | head -1)
if [[ "$CURRENT_SIG" == "Signature=adhoc" ]]; then
  echo "==> Re-signing packaged app with Developer ID (ad-hoc sig detected)..."

  # Patch updater.app Info.plist if missing
  UPDATER_PLIST="$PKG_APP/Contents/MacOS/updater.app/Contents/Info.plist"
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

  for bin in \
    "$PKG_APP/Contents/Resources/plugin-container" \
    "$PKG_APP/Contents/Resources/gmp-clearkey/0.1/libclearkey.dylib" \
    "$PKG_APP/Contents/Library/LaunchServices/org.mozilla.updater"
  do
    [[ -f "$bin" ]] && codesign --force --timestamp --options runtime \
      --sign "$SIGNING_ID" "$bin" 2>/dev/null
  done

  codesign \
    --force --deep --timestamp --options runtime \
    --entitlements "$REPO_ROOT/browser/branding/w3ai/entitlements.plist" \
    --sign "$SIGNING_ID" \
    "$PKG_APP" 2>/dev/null
  echo "    Signed."
fi

mkdir -p "$PROFILE"

# macOS Tahoe (26) blocks unnotarized child process spawning via Gatekeeper.
# Write user.js prefs to disable multi-process mode so websites load in dev.
# Remove this block once the Apple Developer Agreement is renewed and notarized.
SPCTL_RESULT=$(spctl --assess -v "$PKG_APP" 2>&1 || true)
if echo "$SPCTL_RESULT" | grep -q "rejected\|Unnotarized"; then
  echo "    NOTE: Unnotarized build — disabling multi-process mode so websites load."
  cat > "$PROFILE/user.js" << 'USERJS'
// Workaround: macOS Tahoe Gatekeeper blocks unnotarized child processes.
// Single-process mode lets websites load until the build is notarized.
user_pref("browser.tabs.remote.autostart", false);
user_pref("browser.tabs.remote.autostart.2", false);
user_pref("dom.ipc.processCount", 0);
user_pref("dom.ipc.processCount.webIsolated", 0);
user_pref("layers.acceleration.disabled", true);
USERJS
fi

echo "==> Launching TMRW Browser (packaged build)..."
echo "    Profile: $PROFILE"
echo ""

exec "$FIREFOX" -foreground -profile "$PROFILE" "$@"
