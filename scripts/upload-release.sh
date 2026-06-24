#!/usr/bin/env bash
# upload-release.sh — upload existing notarized DMG + create & upload MAR + publish manifest
#
# Run this after notarize.sh has produced a signed DMG, OR after manually placing
# a notarized DMG at:  obj-x86_64-apple-darwin25.5.0/dist/TMRW Browser.dmg
#
# Usage:
#   ./scripts/upload-release.sh             # upload DMG + create & upload MAR + publish
#   ./scripts/upload-release.sh --mar-only  # skip DMG, only upload MAR + publish
#   ./scripts/upload-release.sh --dmg-only  # skip MAR, only upload DMG + publish
#
# On success, local DMG and MAR files are deleted automatically.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
ENV_FILE="$REPO_ROOT/.env"

# ── Load .env ──────────────────────────────────────────────────────────────────
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}" ; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

# ── Args ───────────────────────────────────────────────────────────────────────
MAR_ONLY=false
DMG_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mar-only) MAR_ONLY=true; shift ;;
    --dmg-only) DMG_ONLY=true; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

for var in PUBLISH_SECRET PUBLISH_HMAC_SECRET UPDATE_SERVER_URL; do
  [[ -z "${!var:-}" ]] && { echo "ERROR: $var not set in .env"; exit 1; }
done

BASE_URL="${UPDATE_SERVER_URL}"

# ── Detect version from built app, fall back to .env ──────────────────────────
APP_INI="$OBJ_DIR/dist/firefox/TMRW Browser.app/Contents/Resources/application.ini"
VERSION=""
[[ -f "$APP_INI" ]] && VERSION="$(grep "^Version=" "$APP_INI" | cut -d= -f2)"
[[ -z "$VERSION" ]] && VERSION="${APP_VERSION:-1.0.0}"

BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
SIGNED_DMG="$OBJ_DIR/dist/TMRW Browser.dmg"
MAR_TMPDIR=""
MAR_OUTPUT=""
MAR_SIZE=0
MAR_HASH=""
DMG_SIZE=0
DMG_HASH=""

echo "============================================================"
echo "  TMRW Browser v$VERSION — upload release"
echo "============================================================"
echo ""

# ── Step 1: Validate DMG ──────────────────────────────────────────────────────
if [[ "$MAR_ONLY" != "true" ]]; then
  if [[ ! -f "$SIGNED_DMG" ]]; then
    echo "ERROR: Notarized DMG not found at:"
    echo "  $SIGNED_DMG"
    echo ""
    echo "Run ./scripts/notarize.sh first, or place a signed DMG there manually."
    exit 1
  fi
  DMG_SIZE="$(stat -f%z "$SIGNED_DMG")"
  DMG_HASH="$(shasum -a 512 "$SIGNED_DMG" | awk '{print $1}')"
  echo "DMG: $(( DMG_SIZE / 1024 / 1024 ))MB — ${DMG_HASH:0:16}..."
fi

# ── Step 2: Create MAR ────────────────────────────────────────────────────────
if [[ "$DMG_ONLY" != "true" ]]; then
  PKG_APP="$OBJ_DIR/dist/firefox/TMRW Browser.app"
  if [[ ! -d "$PKG_APP" ]]; then
    echo "ERROR: Packaged app not found at: $PKG_APP"
    echo "Run: ./mach build faster && ./mach package first"
    exit 1
  fi

  echo ""
  echo "==> [1] Creating MAR update package..."
  MAR_TMPDIR="$(mktemp -d)"
  MAR_OUTPUT="$MAR_TMPDIR/tmrw-${VERSION}.complete.mar"
  APP_LINK="$MAR_TMPDIR/app"

  ln -sfn "$PKG_APP" "$APP_LINK"

  (cd "$MAR_TMPDIR" && \
    MAR=/usr/local/bin/mar \
    MOZ_PRODUCT_VERSION="$VERSION" \
    MAR_CHANNEL_ID=default \
    XZ=/usr/local/bin/xz \
      "$REPO_ROOT/tools/update-packaging/make_full_update.sh" \
      "$MAR_OUTPUT" \
      "$APP_LINK" \
      2>&1 | grep -v "^        add\|^ add-if-not\|^      rmdir\|^     remove" || true
  )

  [[ ! -f "$MAR_OUTPUT" && -f "$MAR_TMPDIR/output.mar" ]] && \
    mv "$MAR_TMPDIR/output.mar" "$MAR_OUTPUT"

  if [[ ! -f "$MAR_OUTPUT" ]]; then
    echo "ERROR: MAR creation failed"
    rm -rf "$MAR_TMPDIR"
    exit 1
  fi

  MAR_SIZE="$(stat -f%z "$MAR_OUTPUT")"
  MAR_HASH="$(shasum -a 512 "$MAR_OUTPUT" | awk '{print $1}')"
  echo "    MAR: $(( MAR_SIZE / 1024 / 1024 ))MB — ${MAR_HASH:0:16}..."
fi

# ── Upload helper ─────────────────────────────────────────────────────────────
upload_file() {
  local type="$1" file="$2" label="$3"
  local http_status response tmpout
  tmpout="$(mktemp)"

  http_status=$(curl \
    -X POST "$BASE_URL/api/upload/$type" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -F "version=$VERSION" \
    -F "file=@$file;type=application/octet-stream" \
    --progress-bar \
    -o "$tmpout" \
    -w "%{http_code}" 2>/dev/null)

  response="$(cat "$tmpout")"
  rm -f "$tmpout"

  if [[ "$http_status" != "200" ]]; then
    echo "  ERROR: HTTP $http_status uploading $label"
    echo "  Response: $response"
    return 1
  fi

  echo "    $label uploaded OK — $(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)"
  return 0
}

# ── Step 3: Upload MAR ────────────────────────────────────────────────────────
if [[ "$DMG_ONLY" != "true" && -n "$MAR_OUTPUT" ]]; then
  echo ""
  echo "==> [2] Uploading MAR ($(( MAR_SIZE / 1024 / 1024 ))MB)..."
  if upload_file "mar" "$MAR_OUTPUT" "MAR"; then
    echo "    Deleting local MAR..."
    rm -rf "$MAR_TMPDIR"
    MAR_TMPDIR=""
  else
    rm -rf "$MAR_TMPDIR"
    exit 1
  fi
fi

# ── Step 4: Upload DMG ────────────────────────────────────────────────────────
if [[ "$MAR_ONLY" != "true" ]]; then
  echo ""
  echo "==> [3] Uploading DMG ($(( DMG_SIZE / 1024 / 1024 ))MB)..."
  if upload_file "dmg" "$SIGNED_DMG" "DMG"; then
    echo "    Deleting local DMG..."
    rm -f "$SIGNED_DMG"
  else
    echo "    WARNING: DMG upload failed — keeping local file at:"
    echo "    $SIGNED_DMG"
    echo "    MAR update will still work for existing installs."
  fi
fi

# ── Step 5: Fetch missing hash/size from server if partial upload ─────────────
if [[ "$DMG_ONLY" == "true" || "$MAR_ONLY" == "true" ]]; then
  STATUS=$(curl -sf "$BASE_URL/api/status" 2>/dev/null || echo '{}')
  [[ "$DMG_ONLY" == "true" ]] && {
    MAR_HASH=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('marHash','0'))" 2>/dev/null || echo "0")
    MAR_SIZE=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('marSize',1))" 2>/dev/null || echo "1")
  }
  [[ "$MAR_ONLY" == "true" ]] && {
    DMG_HASH=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dmgHash','0'))" 2>/dev/null || echo "0")
    DMG_SIZE=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dmgSize',1))" 2>/dev/null || echo "1")
  }
fi

# ── Step 6: Publish manifest ──────────────────────────────────────────────────
echo ""
echo "==> [4] Publishing update manifest..."

BODY="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"${MAR_HASH:-0}\",\"marSize\":${MAR_SIZE:-1},\"dmgHash\":\"${DMG_HASH:-0}\",\"dmgSize\":${DMG_SIZE:-1}}"
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" | awk '{print $2}')"

RESPONSE="$(curl -sf -X POST "$BASE_URL/api/publish" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -H "X-Signature: $SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

echo "    $RESPONSE"

echo ""
echo "============================================================"
echo "  Uploaded & Published v$VERSION (build $BUILD_ID)"
echo ""
echo "  Manifest: $BASE_URL/updates/update.xml"
echo "  MAR:      $BASE_URL/download/TMRW-Browser-v${VERSION}.complete.mar"
echo "  DMG:      $BASE_URL/download/TMRW-Browser-v${VERSION}.dmg"
echo ""
echo "  Installed browsers will prompt for update within 6 hours."
echo "  Trigger: Help menu → Check for Updates"
echo "============================================================"

git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (build ${BUILD_ID})" 2>/dev/null || true
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
echo "  Git tag: v${VERSION}"
