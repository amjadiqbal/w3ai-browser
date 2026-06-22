#!/usr/bin/env bash
# publish-update.sh — notarize + upload to Vercel Blob + update tmrw.w3ai.io
#
# Usage:
#   ./scripts/publish-update.sh                      # publish at current APP_VERSION
#   ./scripts/publish-update.sh --bump patch          # 1.0.1 → 1.0.2 then publish
#   ./scripts/publish-update.sh --bump minor          # 1.0.1 → 1.1.0 then publish
#   ./scripts/publish-update.sh --bump major          # 1.0.1 → 2.0.0 then publish
#   ./scripts/publish-update.sh --test-update 1.0.2   # push fake xml for testing only (no build)
# Prerequisites: ./mach build && ./mach package (unless using --test-update)
# Version is controlled via APP_VERSION in .env — all other version files sync from there.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
ENV_FILE="$REPO_ROOT/.env"
VERSION_FILE="$REPO_ROOT/browser/config/version.txt"

# ── Load .env first (APP_VERSION lives here) ───────────────────────────────────
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}" ; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

# APP_VERSION in .env is the source of truth; fall back to version.txt
if [[ -n "${APP_VERSION:-}" ]]; then
  VERSION="$APP_VERSION"
else
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

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

# ── Sync version to all files ──────────────────────────────────────────────────
sync_version() {
  local v="$1"
  echo "$v" > "$VERSION_FILE"
  echo "$v" > "$REPO_ROOT/browser/config/version_display.txt"
  sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$v/" "$ENV_FILE"
  sed -i '' "s/MOZ_APP_VERSION=.*/MOZ_APP_VERSION=$v/" "$REPO_ROOT/mozconfig" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION_DISPLAY=.*/MOZ_APP_VERSION_DISPLAY=$v/" "$REPO_ROOT/mozconfig" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION=.*/MOZ_APP_VERSION=$v/" "$REPO_ROOT/browser/branding/w3ai/configure.sh" 2>/dev/null || true
  sed -i '' "s/MOZ_APP_VERSION_DISPLAY=.*/MOZ_APP_VERSION_DISPLAY=$v/" "$REPO_ROOT/browser/branding/w3ai/configure.sh" 2>/dev/null || true
}

# ── Auto-bump version ──────────────────────────────────────────────────────────
if [[ -n "$BUMP" ]]; then
  IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
  case "$BUMP" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    *) echo "ERROR: --bump must be patch, minor, or major"; exit 1 ;;
  esac
  VERSION="$MAJOR.$MINOR.$PATCH"
  sync_version "$VERSION"
  echo "Bumped version: $VERSION (synced to .env, version.txt, mozconfig, configure.sh)"

  # Commit version bump files and create a matching git tag.
  # Multiple pushes to the same version reuse the existing tag (--force).
  git -C "$REPO_ROOT" add \
    browser/config/version.txt \
    browser/config/version_display.txt \
    mozconfig \
    "browser/branding/w3ai/configure.sh" 2>/dev/null || true
  git -C "$REPO_ROOT" diff --cached --quiet || \
    git -C "$REPO_ROOT" commit -m "chore(release): bump version to $VERSION"
  git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION}"
  git -C "$REPO_ROOT" push origin HEAD --follow-tags --force-with-lease 2>/dev/null || \
    git -C "$REPO_ROOT" push origin HEAD
  git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
  echo "    Git tag v${VERSION} pushed."
fi

# ── Validate required vars ─────────────────────────────────────────────────────
for var in PUBLISH_SECRET PUBLISH_URL VERCEL_BYPASS_SECRET BLOB_READ_WRITE_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in .env"
    exit 1
  fi
done

# ── --test-update: push a version number to update.xml without a real build ───
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
    echo "    NOTE: DMG URL still points to the $VERSION build (same file, test only)."
    echo "    Open Help → About in the installed browser to see the update notification."
  else
    echo "ERROR: HTTP $HTTP_STATUS: $BODY"
    exit 1
  fi
  exit 0
fi

echo "============================================================"
echo "  TMRW Browser v$VERSION — publishing update"
echo "============================================================"
echo ""

# ── Step 1: Notarize ──────────────────────────────────────────────────────────
echo "==> [1/4] Notarizing build..."
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/TMRW Browser.dmg"
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

# ── Step 3: Upload DMG to Vercel Blob ─────────────────────────────────────────
echo ""
echo "==> [3/4] Uploading DMG to Vercel Blob (~215MB, please wait)..."

UPLOAD_TMPDIR="$(mktemp -d)"
trap "rm -rf '$UPLOAD_TMPDIR'" EXIT

(cd "$UPLOAD_TMPDIR" && \
  echo '{"name":"uploader","type":"module"}' > package.json && \
  npm install @vercel/blob --silent 2>/dev/null)

DMG_BLOB_NAME="TMRW-W3-Browser-v${VERSION}.dmg"

cat > "$UPLOAD_TMPDIR/upload.mjs" << 'JSEOF'
import { put, del, list, head } from '@vercel/blob';
import { createReadStream, statSync } from 'fs';

const [,, localPath, blobName] = process.argv;
const token = process.env.BLOB_READ_WRITE_TOKEN;
const localSize = statSync(localPath).size;

// Delete existing blob before uploading to prevent stale chunks from a
// previous partial upload mixing with new data (causes corrupted DMG).
try {
  const { blobs } = await list({ token, prefix: blobName });
  for (const b of blobs) await del(b.url, { token });
} catch (_) {}

const blob = await put(blobName, createReadStream(localPath), {
  access: 'public',
  token,
  contentType: 'application/octet-stream',
  multipart: true,
  allowOverwrite: true,
});

// Verify size via metadata (retry for CDN propagation delay).
for (let i = 0; i <= 5; i++) {
  try {
    const meta = await head(blob.url, { token });
    if (meta.size !== localSize) throw new Error(`SIZE MISMATCH: local=${localSize} remote=${meta.size}`);
    break;
  } catch (e) {
    if (i < 5) await new Promise(r => setTimeout(r, 3000));
    else throw new Error(`Upload verification failed: ${e.message}`);
  }
}

console.log(blob.url);
JSEOF

DMG_URL="$(cd "$UPLOAD_TMPDIR" && \
  BLOB_READ_WRITE_TOKEN="$BLOB_READ_WRITE_TOKEN" \
  node upload.mjs "$SIGNED_DMG" "$DMG_BLOB_NAME")"

if [[ -z "$DMG_URL" ]]; then
  echo "ERROR: Upload returned empty URL"
  exit 1
fi
echo "    Uploaded and verified: $DMG_URL"

# ── Step 4: Publish manifest (retry until server can reach the CDN URL) ────────
echo ""
echo "==> [4/4] Publishing update manifest to tmrw.w3ai.io..."

PAYLOAD="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE,\"dmgUrl\":\"$DMG_URL\",\"notes\":\"${RELEASE_NOTES:-}\"}"

for attempt in 1 2 3 4 5; do
  RESPONSE="$(curl -s -X POST "$PUBLISH_URL" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -H "Content-Type: application/json" \
    -H "User-Agent: TMRW-W3-Publisher/1.0" \
    -H "x-vercel-protection-bypass: ${VERCEL_BYPASS_SECRET}" \
    -d "$PAYLOAD" \
    -w "\n%{http_code}")"
  HTTP_STATUS="$(echo "$RESPONSE" | tail -1)"
  BODY="$(echo "$RESPONSE" | head -1)"

  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "    Success: $BODY"
    break
  fi

  if echo "$BODY" | grep -q "not reachable yet"; then
    echo "    CDN not propagated yet (attempt $attempt/5), waiting 15s..."
    sleep 15
    continue
  fi

  echo "ERROR: Publish failed (HTTP $HTTP_STATUS): $BODY"
  exit 1
done

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "ERROR: Publish failed after 5 attempts — CDN URL never became reachable."
  echo "  URL: $DMG_URL"
  echo "  Try running: ./scripts/publish-update.sh --test-update $VERSION"
  exit 1
fi

echo ""
echo "============================================================"
echo "  Published v$VERSION (build $BUILD_ID)"
echo ""
echo "  Direct download:"
echo "  $DMG_URL"
echo ""
echo "  Manifest: https://tmrw.w3ai.io/updates/update.xml"
echo "  Installed browsers will prompt for update within 6 hours."
echo "  Trigger manually: Help menu → Check for Updates"
echo "============================================================"

# Tag the publish commit so every released version is traceable in git.
# If --bump already tagged above, this is a no-op (same tag, --force).
git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (published build ${BUILD_ID})"
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
echo "  Git tag: v${VERSION}"
