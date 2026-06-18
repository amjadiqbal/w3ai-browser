#!/usr/bin/env bash
# publish-update.sh — notarize + generate update files for tmrw.w3ai.io
#
# What this produces (upload both to your web server at /updates/):
#   - TMRW-W3-Browser.dmg   → the notarized installer
#   - update.xml             → tells installed browsers an update exists
#
# Usage:
#   ./scripts/publish-update.sh
#   Then upload the two files in /tmp/tmrw-publish/ to your server's /updates/ folder.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
VERSION="$(cat "$REPO_ROOT/browser/config/version.txt" | tr -d '[:space:]')"
OUT_DIR="/tmp/tmrw-publish"

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"

echo "============================================================"
echo "  TMRW W3 Browser — publish v$VERSION"
echo "============================================================"
echo ""

# ── Step 1: Notarize ──────────────────────────────────────────────────────────
echo "==> [1/3] Notarizing build..."
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/TMRW W3 Browser.dmg"
cp "$SIGNED_DMG" "$OUT_DIR/TMRW-W3-Browser.dmg"
echo "    Copied DMG to $OUT_DIR/TMRW-W3-Browser.dmg"

# ── Step 2: Get build ID from the packaged app ────────────────────────────────
echo ""
echo "==> [2/3] Reading build ID..."

BUILD_ID="$(defaults read "$OBJ_DIR/dist/TMRW W3 Browser.app/Contents/Info" "BuildID" 2>/dev/null \
  || grep -r "BuildID" "$OBJ_DIR/dist/TMRW W3 Browser.app/Contents/Resources/application.ini" 2>/dev/null | head -1 | cut -d= -f2 \
  || date +%Y%m%d%H%M%S)"

BUILD_ID="${BUILD_ID//[[:space:]]/}"
echo "    Build ID: $BUILD_ID"

DMG_SIZE="$(stat -f%z "$OUT_DIR/TMRW-W3-Browser.dmg")"
DMG_HASH="$(shasum -a 512 "$OUT_DIR/TMRW-W3-Browser.dmg" | awk '{print $1}')"
DMG_URL="https://tmrw.w3ai.io/updates/TMRW-W3-Browser.dmg"

# ── Step 3: Write update.xml ──────────────────────────────────────────────────
echo ""
echo "==> [3/3] Writing update.xml..."

cat > "$OUT_DIR/update.xml" <<EOF
<?xml version="1.0"?>
<updates>
  <update type="minor"
          displayVersion="$VERSION"
          appVersion="$VERSION"
          platformVersion="$VERSION"
          buildID="$BUILD_ID"
          detailsURL="https://tmrw.w3ai.io/releases">
    <patch type="complete"
           URL="$DMG_URL"
           hashFunction="SHA512"
           hashValue="$DMG_HASH"
           size="$DMG_SIZE"/>
  </update>
</updates>
EOF

echo "    build ID : $BUILD_ID"
echo "    version  : $VERSION"
echo "    DMG size : $DMG_SIZE bytes"
echo ""
echo "============================================================"
echo ""
echo "  Two files are ready in: $OUT_DIR/"
echo ""
echo "  UPLOAD BOTH to your web server at:  tmrw.w3ai.io/updates/"
echo ""
echo "    TMRW-W3-Browser.dmg  →  https://tmrw.w3ai.io/updates/TMRW-W3-Browser.dmg"
echo "    update.xml           →  https://tmrw.w3ai.io/updates/update.xml"
echo ""
echo "  Installed browsers will detect the update within 6 hours."
echo "  To trigger immediately: Help menu → Check for Updates"
echo "============================================================"

# ── Optional: auto-upload via rsync/scp if SSH_UPDATE_HOST is set in .env ────
ENV_FILE="$REPO_ROOT/.env"
SSH_HOST=""
SSH_PATH=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}" ; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}"
    [[ "$key" == "SSH_UPDATE_HOST" ]] && SSH_HOST="$val"
    [[ "$key" == "SSH_UPDATE_PATH" ]] && SSH_PATH="$val"
  fi
done < "$ENV_FILE"

if [[ -n "$SSH_HOST" && -n "$SSH_PATH" ]]; then
  echo ""
  echo "==> Auto-uploading via rsync to $SSH_HOST:$SSH_PATH ..."
  rsync -avz --progress "$OUT_DIR/" "$SSH_HOST:$SSH_PATH/"
  echo "    Upload complete. Update is live."
fi
