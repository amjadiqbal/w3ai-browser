#!/usr/bin/env bash
# clean.sh — remove build artifacts, stale DMGs, macOS icon caches, and temp files
#
# Usage:
#   ./scripts/clean.sh            # safe clean (dist artifacts only)
#   ./scripts/clean.sh --all      # deep clean (also wipes the entire obj- dir + icon caches)
#
# After --all you MUST run: ./mach configure && ./mach build faster && ./mach package

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
DIST_DIR="$OBJ_DIR/dist"

DEEP=0
for arg in "$@"; do
  [[ "$arg" == "--all" ]] && DEEP=1
done

echo "============================================================"
echo "  TMRW Browser — Clean"
echo "  Mode: $([ $DEEP -eq 1 ] && echo "DEEP (--all)" || echo "safe")"
echo "============================================================"
echo ""

# ── 1. Stale DMGs in dist (keep only the newest one per version) ──────────────
echo "==> Removing stale DMGs and build artifacts from dist/..."
if [[ -d "$DIST_DIR" ]]; then
  # Delete every .dmg whose name doesn't match the current app name
  find "$DIST_DIR" -maxdepth 1 -name "*.dmg" | while read -r f; do
    echo "    rm $f"
    rm -f "$f"
  done
  # Delete stale app bundles (any .app that isn't the current one)
  find "$DIST_DIR" -maxdepth 1 -name "*.app" -not -name "TMRW Browser.app" | while read -r f; do
    echo "    rm -rf $f"
    rm -rf "$f"
  done
  # Delete leftover package artifacts
  find "$DIST_DIR" -maxdepth 1 \( \
    -name "*.txt" -o -name "*.zip" -o -name "*.mar" \
  \) | while read -r f; do
    echo "    rm $f"
    rm -f "$f"
  done
fi
echo "    Done."

# ── 2. Notarization temp dir ───────────────────────────────────────────────────
echo ""
echo "==> Removing notarization temp files..."
rm -rf /tmp/tmrw-notarize
echo "    Done."

# ── 3. Stale MozillaUpdateLock files ──────────────────────────────────────────
echo ""
echo "==> Removing stale MozillaUpdateLock files from /tmp..."
find /tmp -maxdepth 1 -name "MozillaUpdateLock-*" -delete 2>/dev/null || true
echo "    Done."

# ── 4. Leftover iconset/icns temp files ───────────────────────────────────────
echo ""
echo "==> Removing icon temp files from /tmp..."
find /tmp -maxdepth 1 \( -name "*.iconset" -o -name "*.icns" \) -exec rm -rf {} + 2>/dev/null || true
echo "    Done."

# ── 5. macOS icon + dock cache (always safe to clear) ─────────────────────────
echo ""
echo "==> Resetting macOS icon and dock cache..."
rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.iconservices 2>/dev/null || true
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -kill -r -domain local -domain system -domain user 2>/dev/null || true
killall Dock 2>/dev/null || true
echo "    Icon cache cleared and Dock restarted."

if [[ $DEEP -eq 1 ]]; then
  echo ""
  echo "==> [--all] Wiping entire obj- build directory (~2-3 GB)..."
  rm -rf "$OBJ_DIR"
  echo "    Done. IMPORTANT — artifact build requires 3 steps to rebuild:"
  echo "      1. ./mach configure           (recreate obj- dir)"
  echo "      2. ./mach artifact install    (re-download pre-built Firefox binaries ~1 GB)"
  echo "      3. ./mach build faster        (compile only our JS/frontend changes)"
  echo "      4. ./mach package             (optional: create DMG)"
  echo ""
  echo "    NOTE: 'mach artifact install' is mandatory after --all. Without it,"
  echo "    './mach build' searches 500 pushheads and fails with 'no built artifacts found'."
fi

echo ""
echo "============================================================"
echo "  Clean complete."
echo "============================================================"
