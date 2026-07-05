#!/usr/bin/env bash
set -euo pipefail

# clear-old-testflight-install.sh — remove a previously installed TMRW/W3Ai
# TestFlight build and its runtime caches/profiles/preferences/crash reports
# before installing a fresh TestFlight build, so stale data can't confuse
# testing (e.g. an old profile masking whether a packaging fix actually
# worked). This only touches the *installed, running-app* side of things —
# it never touches source, obj build output, dist pkgs, provisioning
# profiles, or .env. See scripts/package-testflight-macos.sh for the build
# side of the pipeline.
#
# Usage:
#   ./scripts/clear-old-testflight-install.sh --clear=old

APP_BUNDLE_ID="com.tmrw.w3ai"
INSTALLED_APP="/Applications/TMRW.app"
CRASH_BACKUP_DIR="$HOME/Desktop/tmrw-old-crashes"
DIAGNOSTIC_REPORTS_DIR="$HOME/Library/Logs/DiagnosticReports"
CRASHREPORTER_SUPPORT_DIR="$HOME/Library/Application Support/CrashReporter"

# Paths intentionally NOT removed by default (developer/tool caches unrelated
# to a TestFlight install) — only reported if present.
XCODE_PRODUCTS_PATH="$HOME/Library/Developer/Xcode/Products/io.w3ai.sip"
CLAUDE_CACHE_PATH="$HOME/Library/Caches/claude-cli-nodejs/-Volumes-Amjad-Plato-W3Ai"

print_usage() {
  cat <<'EOF'
Usage:
  ./scripts/clear-old-testflight-install.sh --clear=old

Options:
  --clear=old     Remove previously installed TMRW/TestFlight app, caches, profiles, preferences, containers, and old crash reports.
  --help          Show this help.
EOF
}

note() { echo "==> $*"; }

if [ "$#" -eq 0 ]; then
  print_usage
  exit 0
fi

case "${1:-}" in
  --help)
    print_usage
    exit 0
    ;;
  --clear=old)
    ;;
  *)
    print_usage
    exit 0
    ;;
esac

note "Quitting running app instances..."
osascript -e 'quit app "TMRW"' 2>/dev/null || true
osascript -e 'quit app "TestFlight"' 2>/dev/null || true

pkill -f "TMRW" 2>/dev/null || true
pkill -f "firefox" 2>/dev/null || true
pkill -f "plugin-container" 2>/dev/null || true
pkill -f "crashreporter" 2>/dev/null || true
pkill -f "crashhelper" 2>/dev/null || true

note "Removing old installed app: $INSTALLED_APP"
sudo rm -rf "$INSTALLED_APP"
ls -la "$INSTALLED_APP" 2>/dev/null || echo "TMRW.app removed"

note "Removing app containers and application scripts..."
if ! sudo rm -rf "$HOME/Library/Containers/$APP_BUNDLE_ID" 2>/tmp/tmrw-cleanup-container-err.$$; then
  if grep -q "Operation not permitted" /tmp/tmrw-cleanup-container-err.$$ 2>/dev/null; then
    echo "WARNING: macOS denied removal of container metadata. Enable Full Disk Access for Terminal:"
    echo "  System Settings -> Privacy & Security -> Full Disk Access -> enable Terminal/iTerm."
    echo "  Then rerun this script."
  else
    cat /tmp/tmrw-cleanup-container-err.$$ >&2 || true
  fi
fi
rm -f /tmp/tmrw-cleanup-container-err.$$
rm -rf "$HOME/Library/Application Scripts/$APP_BUNDLE_ID"

note "Removing TMRW/W3Ai/Mozilla profile and app support paths..."
rm -rf "$HOME/Library/Application Support/TMRW"
rm -rf "$HOME/Library/Application Support/W3Ai"
rm -rf "$HOME/Library/Application Support/TMRW Browser"
rm -rf "$HOME/Library/Application Support/com.tmrw.w3ai"
rm -rf "$HOME/Library/Application Support/org.mozilla.tmrwbrowser"
rm -rf "$HOME/Library/Application Support/org.mozilla.w3ai"
rm -rf "$HOME/Library/Application Support/org.w3ai.browser"
rm -rf "$HOME/Library/Application Support/org.mozilla.org.w3ai.browser"

note "Removing cache paths..."
rm -rf "$HOME/Library/Caches/TMRW"
rm -rf "$HOME/Library/Caches/W3Ai"
rm -rf "$HOME/Library/Caches/TMRW Browser"
rm -rf "$HOME/Library/Caches/com.tmrw.w3ai"
rm -rf "$HOME/Library/Caches/org.mozilla.tmrwbrowser"
rm -rf "$HOME/Library/Caches/org.mozilla.w3ai"
rm -rf "$HOME/Library/Caches/org.w3ai.browser"
rm -rf "$HOME/Library/Caches/org.mozilla.org.w3ai.browser"

note "Removing saved application state..."
rm -rf "$HOME/Library/Saved Application State/com.tmrw.w3ai.savedState"
rm -rf "$HOME/Library/Saved Application State/org.mozilla.tmrwbrowser.savedState"
rm -rf "$HOME/Library/Saved Application State/org.w3ai.browser.savedState"

note "Removing preference plist files..."
rm -f "$HOME/Library/Preferences/com.tmrw.w3ai.plist"
rm -f "$HOME/Library/Preferences/org.mozilla.tmrwbrowser.plist"
rm -f "$HOME/Library/Preferences/org.mozilla.org.w3ai.browser.plist"
rm -f "$HOME/Library/Preferences/org.w3ai.browser.plist"
rm -f "$HOME/Library/Preferences/org.mozilla.w3ai.plist"

note "Backing up matching old crash reports (not deleting all CrashReporter files)..."
mkdir -p "$CRASH_BACKUP_DIR"
find "$DIAGNOSTIC_REPORTS_DIR" \
  -type f \
  \( -iname "*TMRW*" -o -iname "*W3Ai*" -o -iname "*w3ai*" -o -iname "*firefox*" -o -iname "*plugin-container*" -o -iname "*crashreporter*" -o -iname "*crashhelper*" \) \
  -exec mv {} "$CRASH_BACKUP_DIR/" \; 2>/dev/null || true

find "$CRASHREPORTER_SUPPORT_DIR" \
  -type f \
  \( -iname "*TMRW*" -o -iname "*W3Ai*" -o -iname "*w3ai*" -o -iname "*firefox*" -o -iname "*plugin-container*" -o -iname "*crashreporter*" -o -iname "*crashhelper*" \) \
  -delete 2>/dev/null || true

note "Checking optional developer/tool caches (not removed by default)..."
if [ -e "$XCODE_PRODUCTS_PATH" ]; then
  echo "not removed developer/tool cache: $XCODE_PRODUCTS_PATH"
fi
if [ -e "$CLAUDE_CACHE_PATH" ]; then
  echo "not removed developer/tool cache: $CLAUDE_CACHE_PATH"
fi

echo ""
echo "Remaining TMRW/W3Ai files:"
find "$HOME/Library" -maxdepth 4 \
  \( -iname "*tmrw*" -o -iname "*w3ai*" \) \
  -print 2>/dev/null || true

echo ""
echo "Remaining app:"
find /Applications -maxdepth 2 \
  \( -iname "*TMRW*.app" -o -iname "*W3*.app" -o -iname "*W3Ai*.app" \) \
  -print 2>/dev/null || true

echo ""
echo "Cleanup complete. Now install the fresh TMRW build from TestFlight."
