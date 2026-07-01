#!/usr/bin/env bash
# clean.sh — remove build artifacts, stale DMGs, macOS icon caches, and temp files
#
# Usage:
#   ./scripts/clean.sh            # safe clean (dist artifacts only)
#   ./scripts/clean.sh --all      # deep clean (wipes obj- dir, then auto-recovers artifacts)
#
# --all automatically runs: configure → extract cached jars → restore missing bundles → build faster

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
DIST_DIR="$OBJ_DIR/dist"
MOZBUILD_CACHE="$HOME/.mozbuild/package-frontend"

DEEP=0
for arg in "$@"; do
  [[ "$arg" == "--all" ]] && DEEP=1
done

echo "============================================================"
echo "  TMRW Browser — Clean"
echo "  Mode: $([ $DEEP -eq 1 ] && echo "DEEP (--all)" || echo "safe")"
echo "============================================================"
echo ""

# ── 1. Stale DMGs and build artifacts from dist/ ──────────────────────────────
echo "==> Removing stale DMGs and build artifacts from dist/..."
if [[ -d "$DIST_DIR" ]]; then
  find "$DIST_DIR" -maxdepth 1 -name "*.dmg" -delete 2>/dev/null || true
  find "$DIST_DIR" -maxdepth 1 -name "*.app" -not -name "TMRW Browser.app" \
    -exec rm -rf {} + 2>/dev/null || true
  find "$DIST_DIR" -maxdepth 1 \( -name "*.txt" -o -name "*.zip" -o -name "*.mar" \) \
    -delete 2>/dev/null || true
fi
echo "    Done."

# ── 2. Notarization temp dir ───────────────────────────────────────────────────
echo ""
echo "==> Removing notarization temp files..."
rm -rf /tmp/tmrw-notarize
echo "    Done."

# ── 3. Stale MozillaUpdateLock + icon temp files in /tmp ──────────────────────
echo ""
echo "==> Removing stale lock and icon temp files from /tmp..."
find /tmp -maxdepth 1 -name "MozillaUpdateLock-*" -delete 2>/dev/null || true
find /tmp -maxdepth 1 \( -name "*.iconset" -o -name "*.icns" \) -exec rm -rf {} + 2>/dev/null || true
echo "    Done."

# ── 4. macOS icon + dock cache ─────────────────────────────────────────────────
echo ""
echo "==> Resetting macOS icon and dock cache..."
rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.iconservices 2>/dev/null || true
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -kill -r -domain local -domain system -domain user 2>/dev/null || true
killall Dock 2>/dev/null || true
echo "    Icon cache cleared and Dock restarted."

# ── 5. Deep clean: wipe obj- and auto-recover ─────────────────────────────────
if [[ $DEEP -eq 1 ]]; then
  echo ""
  echo "==> [--all] Wiping entire obj- build directory..."
  rm -rf "$OBJ_DIR"
  echo "    Done."

  echo ""
  echo "==> [--all] Reconfiguring..."
  cd "$REPO_ROOT"
  ./mach configure
  echo "    Done."

  echo ""
  echo "==> [--all] Restoring artifact binaries from local cache (~/.mozbuild)..."
  # mach artifact install fails on custom forks ("Tried 500 pushheads").
  # Instead extract the most recent cached processed jars directly.
  LATEST_DMG_JAR="$(ls -t "$MOZBUILD_CACHE"/*-target.dmg.processed.jar 2>/dev/null | head -1)"
  LATEST_XPT_JAR="$(ls -t "$MOZBUILD_CACHE"/*-target.xpt_artifacts.zip.processed.jar 2>/dev/null | head -1)"
  LATEST_UPD_JAR="$(ls -t "$MOZBUILD_CACHE"/*-target.update_framework_artifacts.zip.processed.jar 2>/dev/null | head -1)"

  if [[ -z "$LATEST_DMG_JAR" ]]; then
    echo "ERROR: No cached artifact jars found in $MOZBUILD_CACHE"
    echo "Run on a machine that previously built successfully, or do a full ./mach build."
    exit 1
  fi

  echo "    Using: $(basename "$LATEST_DMG_JAR")"
  unzip -q -o "$LATEST_DMG_JAR" -d "$OBJ_DIR"
  [[ -n "$LATEST_XPT_JAR" ]] && unzip -q -o "$LATEST_XPT_JAR" -d "$OBJ_DIR"
  [[ -n "$LATEST_UPD_JAR" ]] && unzip -q -o "$LATEST_UPD_JAR" -d "$OBJ_DIR"

  # The jar extracts compiled binaries to obj-/bin/ but the build system
  # expects them at obj-/dist/bin/. Use rsync (handles dirs + files, no glob limit).
  echo "    Copying binaries: bin/ → dist/bin/..."
  mkdir -p "$OBJ_DIR/dist/bin"
  rsync -a --ignore-existing "$OBJ_DIR/bin/" "$OBJ_DIR/dist/bin/"
  # Verify the critical binary made it across
  if [[ ! -f "$OBJ_DIR/dist/bin/firefox" ]]; then
    echo "ERROR: dist/bin/firefox still missing after rsync. Check $OBJ_DIR/bin/:"
    ls "$OBJ_DIR/bin/" | head -10
    exit 1
  fi
  echo "    firefox binary confirmed at dist/bin/firefox"

  # Build the updater.app sub-bundle that the repackage step requires
  echo "    Building updater.app bundle..."
  UPDATER_APP="$OBJ_DIR/dist/bin/updater.app"
  rm -rf "$UPDATER_APP"
  mkdir -p "$UPDATER_APP/Contents/MacOS"
  mkdir -p "$UPDATER_APP/Contents/Frameworks/UpdateSettings.framework/Resources"
  rsync -a --exclude "*.in" \
    "$REPO_ROOT/toolkit/mozapps/update/updater/macbuild/Contents/" \
    "$UPDATER_APP/Contents/"
  cp "$OBJ_DIR/dist/bin/org.mozilla.updater" "$UPDATER_APP/Contents/MacOS/org.mozilla.updater"
  chmod +x "$UPDATER_APP/Contents/MacOS/org.mozilla.updater"
  UPSETTINGS="$(find "$OBJ_DIR/update_framework_artifacts" -name "UpdateSettings" 2>/dev/null | head -1)"
  [[ -n "$UPSETTINGS" ]] && cp "$UPSETTINGS" \
    "$UPDATER_APP/Contents/Frameworks/UpdateSettings.framework/UpdateSettings" || true
  cp "$REPO_ROOT/toolkit/mozapps/update/updater/macos-frameworks/UpdateSettings/Info.plist" \
    "$UPDATER_APP/Contents/Frameworks/UpdateSettings.framework/Resources/Info.plist" 2>/dev/null || true

  # Build ChannelPrefs.framework that repackage moves to Contents/Frameworks/
  echo "    Building ChannelPrefs.framework..."
  CHANNEL_DEST="$OBJ_DIR/dist/bin/ChannelPrefs.framework"
  mkdir -p "$CHANNEL_DEST/Resources"
  CHANNEL_BIN="$(find "$OBJ_DIR/update_framework_artifacts" -name "ChannelPrefs" 2>/dev/null | head -1)"
  [[ -n "$CHANNEL_BIN" ]] && cp "$CHANNEL_BIN" "$CHANNEL_DEST/ChannelPrefs" || true
  cp "$REPO_ROOT/toolkit/mozapps/macos-frameworks/ChannelPrefs/Info.plist" \
    "$CHANNEL_DEST/Resources/Info.plist" 2>/dev/null || true

  echo "    Artifact recovery complete."
  echo ""
  echo "==> [--all] Building (./mach build faster)..."
  ./mach build faster
  echo ""
  echo "    Build complete. Run './mach package' to create a fresh DMG."
fi

echo ""
echo "============================================================"
echo "  Clean complete."
echo "============================================================"
