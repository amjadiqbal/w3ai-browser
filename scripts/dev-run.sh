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

# plugin-container needs @executable_path/../MacOS in its rpath so it can find
# XUL, libnss3, and libmozglue from Contents/MacOS/ at runtime.
# install_name_tool invalidates the signature, so run this BEFORE signing.
PC_BIN="$PKG_APP/Contents/Resources/plugin-container"
if ! otool -l "$PC_BIN" 2>/dev/null | grep -q "@executable_path/../MacOS"; then
  echo "==> Adding MacOS rpath to plugin-container..."
  install_name_tool -add_rpath "@executable_path/../MacOS" "$PC_BIN" 2>/dev/null || true
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

  # plugin-container must be signed with JIT + disable-library-validation
  # entitlements — without allow-jit the JS engine can't compile and the child
  # process exits immediately with status 1 (silent crash, no crash dump).
  [[ -f "$PKG_APP/Contents/Resources/plugin-container" ]] && \
    codesign --force --timestamp --options runtime \
      --entitlements "$REPO_ROOT/browser/branding/w3ai/entitlements.plist" \
      --sign "$SIGNING_ID" \
      "$PKG_APP/Contents/Resources/plugin-container" 2>/dev/null

  for bin in \
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

# Firefox on macOS requires plugin-container to be in a .app sub-bundle under
# Contents/MacOS/ (path: plugin-container.app/Contents/MacOS/plugin-container).
# The build system produces a flat binary in Contents/Resources/ but does not
# create this bundle structure, causing posix_spawnp to fail (Error:0) and
# every page to load blank. Create it once if absent.
PC_BUNDLE="$PKG_APP/Contents/MacOS/plugin-container.app"
if [[ ! -x "$PC_BUNDLE/Contents/MacOS/plugin-container" ]]; then
  echo "==> Creating plugin-container.app sub-bundle (one-time setup)..."
  mkdir -p "$PC_BUNDLE/Contents/MacOS"
  ln -sf "../../../../Resources/plugin-container" \
    "$PC_BUNDLE/Contents/MacOS/plugin-container"
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

echo "==> Launching TMRW Browser (packaged build)..."
echo "    Profile: $PROFILE"
echo ""

exec "$FIREFOX" -foreground -profile "$PROFILE" "$@"
