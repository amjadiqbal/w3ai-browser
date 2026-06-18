#!/usr/bin/env bash
# publish-update.sh — notarize + upload to Vercel Blob + update tmrw.w3ai.io
#
# Usage: ./scripts/publish-update.sh
# Prerequisites: ./mach build && ./mach package

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
VERSION="$(cat "$REPO_ROOT/browser/config/version.txt" | tr -d '[:space:]')"

# ── Load .env ──────────────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}" ; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

# ── Validate required vars ─────────────────────────────────────────────────────
for var in PUBLISH_SECRET PUBLISH_URL BLOB_READ_WRITE_TOKEN VERCEL_BYPASS_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in .env"
    exit 1
  fi
done

echo "============================================================"
echo "  TMRW W3 Browser v$VERSION — publishing update"
echo "============================================================"
echo ""

# ── Step 1: Notarize ──────────────────────────────────────────────────────────
echo "==> [1/4] Notarizing build..."
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/TMRW W3 Browser.dmg"
if [[ ! -f "$SIGNED_DMG" ]]; then
  echo "ERROR: Notarized DMG not found at $SIGNED_DMG"
  exit 1
fi

DMG_SIZE="$(stat -f%z "$SIGNED_DMG")"
DMG_HASH="$(shasum -a 512 "$SIGNED_DMG" | awk '{print $1}')"
echo "    DMG size: $DMG_SIZE bytes"

# ── Step 2: Get build ID ───────────────────────────────────────────────────────
echo ""
echo "==> [2/4] Reading build ID..."
BUILD_ID="$(grep "^BuildID" \
  "$OBJ_DIR/dist/TMRW W3 Browser.app/Contents/Resources/application.ini" \
  2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
BUILD_ID="${BUILD_ID:-$(date +%Y%m%d%H%M%S)}"
echo "    Build ID: $BUILD_ID"

# ── Step 3: Upload DMG to Vercel Blob ─────────────────────────────────────────
echo ""
echo "==> [3/4] Uploading DMG to Vercel Blob (~215MB, please wait)..."

BLOB_RESPONSE="$(curl -s -X PUT \
  "https://blob.vercel-storage.com/TMRW-W3-Browser-v${VERSION}.dmg" \
  -H "Authorization: Bearer $BLOB_READ_WRITE_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  -H "x-content-type: application/octet-stream" \
  --data-binary "@$SIGNED_DMG")"

DMG_URL="$(echo "$BLOB_RESPONSE" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)"

if [[ -z "$DMG_URL" ]]; then
  echo "ERROR: Blob upload failed. Response: $BLOB_RESPONSE"
  exit 1
fi
echo "    Uploaded: $DMG_URL"

# ── Step 4: POST metadata to Vercel API ───────────────────────────────────────
echo ""
echo "==> [4/4] Publishing update manifest to tmrw.w3ai.io..."

RESPONSE="$(curl -s -X POST "$PUBLISH_URL" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -H "Content-Type: application/json" \
  -H "User-Agent: TMRW-W3-Publisher/1.0" \
  -H "x-vercel-protection-bypass: ${VERCEL_BYPASS_SECRET}" \
  -d "{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE,\"dmgUrl\":\"$DMG_URL\"}" \
  -w "\n%{http_code}")"

HTTP_STATUS="$(echo "$RESPONSE" | tail -1)"
BODY="$(echo "$RESPONSE" | head -1)"

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "    Success: $BODY"
else
  echo "ERROR: Publish failed (HTTP $HTTP_STATUS): $BODY"
  exit 1
fi

echo ""
echo "============================================================"
echo "  Published v$VERSION (build $BUILD_ID)"
echo ""
echo "  Direct download (share this with testers):"
echo "  $DMG_URL"
echo ""
echo "  Manifest: https://tmrw.w3ai.io/updates/update.xml"
echo "  Installed browsers will prompt for update within 6 hours."
echo "  Trigger manually: Help menu → Check for Updates"
echo "============================================================"
