#!/usr/bin/env bash
# publish-update.sh — notarize + upload to Vercel Blob + update tmrw.w3ai.io
#
# Usage:
#   ./scripts/publish-update.sh                   # publish at current version
#   ./scripts/publish-update.sh --bump patch       # 1.0.0 → 1.0.1 then publish
#   ./scripts/publish-update.sh --bump minor       # 1.0.0 → 1.1.0 then publish
#   ./scripts/publish-update.sh --bump major       # 1.0.0 → 2.0.0 then publish
#   ./scripts/publish-update.sh --test-update 1.0.1  # push fake xml for testing only (no build)
# Prerequisites: ./mach build && ./mach package (unless using --test-update)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
VERSION_FILE="$REPO_ROOT/browser/config/version.txt"
VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

# ── Parse flags ────────────────────────────────────────────────────────────────
BUMP=""
TEST_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) BUMP="$2"; shift 2 ;;
    --test-update) TEST_VERSION="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ── Auto-bump version ──────────────────────────────────────────────────────────
if [[ -n "$BUMP" ]]; then
  IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
  case "$BUMP" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    *) echo "ERROR: --bump must be patch, minor, or major"; exit 1 ;;
  esac
  NEW_VERSION="$MAJOR.$MINOR.$PATCH"
  echo "$NEW_VERSION" > "$VERSION_FILE"
  sed -i '' "s/MOZ_APP_VERSION=.*/MOZ_APP_VERSION=$NEW_VERSION/" "$REPO_ROOT/mozconfig" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION_DISPLAY=.*/MOZ_APP_VERSION_DISPLAY=$NEW_VERSION/" "$REPO_ROOT/mozconfig" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION=.*/MOZ_APP_VERSION=$NEW_VERSION/" "$REPO_ROOT/browser/branding/w3ai/configure.sh" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION_DISPLAY=.*/MOZ_APP_VERSION_DISPLAY=$NEW_VERSION/" "$REPO_ROOT/browser/branding/w3ai/configure.sh" 2>/dev/null || true
  VERSION="$NEW_VERSION"
  echo "Bumped version: $VERSION"
fi

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
for var in PUBLISH_SECRET PUBLISH_URL VERCEL_BYPASS_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in .env"
    exit 1
  fi
done

# ── --test-update: just push a version number to update.xml, no build needed ──
if [[ -n "$TEST_VERSION" ]]; then
  echo "==> Pushing test update.xml: installed=$VERSION → advertised=$TEST_VERSION"
  EXISTING=$(curl -s https://tmrw.w3ai.io/updates/update.xml)
  DMG_URL=$(echo "$EXISTING" | grep -o 'URL="[^"]*"' | head -1 | cut -d'"' -f2)
  DMG_HASH=$(echo "$EXISTING" | grep -o 'hashValue="[^"]*"' | cut -d'"' -f2)
  DMG_SIZE=$(echo "$EXISTING" | grep -o 'size="[^"]*"' | cut -d'"' -f2)
  BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
  RESPONSE="$(curl -s -X POST "$PUBLISH_URL" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -H "Content-Type: application/json" \
    -H "User-Agent: TMRW-W3-Publisher/1.0" \
    -H "x-vercel-protection-bypass: ${VERCEL_BYPASS_SECRET}" \
    -d "{\"version\":\"$TEST_VERSION\",\"buildID\":\"$BUILD_ID\",\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE,\"dmgUrl\":\"$DMG_URL\"}" \
    -w "\n%{http_code}")"
  HTTP_STATUS="$(echo "$RESPONSE" | tail -1)"
  BODY="$(echo "$RESPONSE" | head -1)"
  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "    update.xml now shows appVersion=$TEST_VERSION"
    echo "    Open Help → About in the browser to see the update notification."
  else
    echo "ERROR: HTTP $HTTP_STATUS: $BODY"
    exit 1
  fi
  exit 0
fi

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
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
echo "    Build ID: $BUILD_ID"

# ── Step 3: Upload DMG to Vercel Blob (multipart via @vercel/blob SDK) ─────────
echo ""
echo "==> [3/4] Uploading DMG to Vercel Blob (~215MB, please wait)..."

UPLOAD_TMPDIR="$(mktemp -d)"
trap "rm -rf '$UPLOAD_TMPDIR'" EXIT

# Bootstrap @vercel/blob in a temp dir
(cd "$UPLOAD_TMPDIR" && \
  echo '{"name":"uploader","type":"module"}' > package.json && \
  npm install @vercel/blob --silent 2>/dev/null)

cat > "$UPLOAD_TMPDIR/upload.mjs" << 'JSEOF'
import { put } from '@vercel/blob';
import { createReadStream } from 'fs';
const url = (await put(process.argv[3], createReadStream(process.argv[2]), {
  access: 'public',
  token: process.env.BLOB_READ_WRITE_TOKEN,
  contentType: 'application/octet-stream',
  multipart: true,
  allowOverwrite: true,
})).url;
console.log(url);
JSEOF

DMG_URL="$(cd "$UPLOAD_TMPDIR" && \
  BLOB_READ_WRITE_TOKEN="$BLOB_READ_WRITE_TOKEN" \
  node upload.mjs "$SIGNED_DMG" "TMRW-W3-Browser-v${VERSION}.dmg")"

if [[ -z "$DMG_URL" ]]; then
  echo "ERROR: Upload returned empty URL"
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
  -d "{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE,\"dmgUrl\":\"$DMG_URL\",\"notes\":\"${RELEASE_NOTES:-}\"}" \
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
