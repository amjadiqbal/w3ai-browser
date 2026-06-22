#!/usr/bin/env bash
# publish-update.sh — notarize + upload to self-hosted update server + update manifest
#
# Usage:
#   ./scripts/publish-update.sh                      # publish at current APP_VERSION
#   ./scripts/publish-update.sh --bump patch          # 1.0.6 → 1.0.7 then publish
#   ./scripts/publish-update.sh --bump minor          # 1.0.6 → 1.1.0 then publish
#   ./scripts/publish-update.sh --bump major          # 1.0.6 → 2.0.0 then publish
#   ./scripts/publish-update.sh --test-update 1.0.7   # push fake xml for testing only (no build)
# Prerequisites: ./mach build faster && ./mach package (unless using --test-update)
# Version is controlled via APP_VERSION in .env — all other version files sync from there.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
ENV_FILE="$REPO_ROOT/.env"
VERSION_FILE="$REPO_ROOT/browser/config/version.txt"

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}" ; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}" ; val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

if [[ -n "${APP_VERSION:-}" ]]; then
  VERSION="$APP_VERSION"
else
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

BUMP=""
TEST_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) BUMP="$2"; shift 2 ;;
    --test-update) TEST_VERSION="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

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
  echo "Bumped version: $VERSION"
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

for var in PUBLISH_SECRET PUBLISH_HMAC_SECRET UPDATE_SERVER_URL; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in .env"
    exit 1
  fi
done

BASE_URL="${UPDATE_SERVER_URL}"   # e.g. https://tmrw-update.w3ai.io

# ── --test-update: bump the manifest without a real build ────────────────────
if [[ -n "$TEST_VERSION" ]]; then
  echo "==> Pushing test manifest: installed=$VERSION → advertised=$TEST_VERSION"
  EXISTING=$(curl -sf "$BASE_URL/api/status" || echo '{}')
  MAR_HASH=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('marHash','0'*128))" 2>/dev/null || echo '0')
  BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
  BODY="{\"version\":\"$TEST_VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"$MAR_HASH\",\"marSize\":1}"
  SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" -hex | awk '{print $2}')"
  curl -sf -X POST "$BASE_URL/api/publish" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -H "X-Signature: $SIG" \
    -H "Content-Type: application/json" \
    -d "$BODY"
  echo ""
  echo "    update.xml now shows appVersion=$TEST_VERSION"
  exit 0
fi

echo "============================================================"
echo "  TMRW Browser v$VERSION — publishing update"
echo "============================================================"
echo ""

# ── Step 1: Notarize ──────────────────────────────────────────────────────────
echo "==> [1/5] Notarizing build..."
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/TMRW Browser.dmg"
if [[ ! -f "$SIGNED_DMG" ]]; then
  echo "ERROR: Notarized DMG not found at $SIGNED_DMG"
  exit 1
fi

DMG_SIZE="$(stat -f%z "$SIGNED_DMG")"
DMG_HASH="$(shasum -a 512 "$SIGNED_DMG" | awk '{print $1}')"
echo "    DMG size: $DMG_SIZE bytes"

# ── Step 2: Create complete MAR update package ────────────────────────────────
echo ""
echo "==> [2/5] Creating complete MAR update package..."

MAR_TMPDIR="$(mktemp -d)"
MAR_OUTPUT="$MAR_TMPDIR/tmrw-${VERSION}.complete.mar"
APP_LINK="$MAR_TMPDIR/app"

ln -sfn "$OBJ_DIR/dist/firefox/TMRW Browser.app" "$APP_LINK"

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

if [[ ! -f "$MAR_OUTPUT" && -f "$MAR_TMPDIR/output.mar" ]]; then
  /bin/mv "$MAR_TMPDIR/output.mar" "$MAR_OUTPUT"
fi

if [[ ! -f "$MAR_OUTPUT" ]]; then
  echo "ERROR: MAR creation failed — $MAR_OUTPUT not found"
  exit 1
fi

MAR_SIZE="$(stat -f%z "$MAR_OUTPUT")"
MAR_HASH="$(shasum -a 512 "$MAR_OUTPUT" | awk '{print $1}')"
echo "    MAR size: $MAR_SIZE bytes"
echo "    MAR hash: ${MAR_HASH:0:16}..."

BUILD_ID="$(date -u +%Y%m%d%H%M%S)"

# ── Step 3: Upload MAR to update server ───────────────────────────────────────
echo ""
echo "==> [3/5] Uploading MAR to update server..."

MAR_UPLOAD=$(curl -sf \
  -X POST "$BASE_URL/api/upload/mar" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -F "version=$VERSION" \
  -F "file=@$MAR_OUTPUT;type=application/octet-stream" \
  --progress-bar 2>&1 | tail -1)

echo "    MAR: $(echo "$MAR_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url','?'))" 2>/dev/null || echo "$MAR_UPLOAD")"

# ── Step 4: Upload DMG to update server ───────────────────────────────────────
echo ""
echo "==> [4/5] Uploading DMG to update server (~$(( DMG_SIZE / 1024 / 1024 ))MB)..."

DMG_UPLOAD=$(curl -sf \
  -X POST "$BASE_URL/api/upload/dmg" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -F "version=$VERSION" \
  -F "file=@$SIGNED_DMG;type=application/octet-stream" \
  --progress-bar 2>&1 | tail -1)

echo "    DMG: $(echo "$DMG_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url','?'))" 2>/dev/null || echo "$DMG_UPLOAD")"

rm -rf "$MAR_TMPDIR"

# ── Step 5: Publish manifest ───────────────────────────────────────────────────
echo ""
echo "==> [5/5] Publishing update manifest..."

BODY="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"$MAR_HASH\",\"marSize\":$MAR_SIZE,\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE}"
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" | awk '{print $2}')"

RESPONSE="$(curl -sf -X POST "$BASE_URL/api/publish" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -H "X-Signature: $SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

echo "    Success: $RESPONSE"

echo ""
echo "============================================================"
echo "  Published v$VERSION (build $BUILD_ID)"
echo ""
echo "  Manifest: $BASE_URL/updates/update.xml"
echo "  MAR:      $BASE_URL/download/TMRW-Browser-v${VERSION}.complete.mar"
echo "  DMG:      $BASE_URL/download/TMRW-Browser-v${VERSION}.dmg"
echo ""
echo "  Installed browsers will prompt for update within 6 hours."
echo "  Trigger manually: Help menu → Check for Updates"
echo "============================================================"

git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (published build ${BUILD_ID})"
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
echo "  Git tag: v${VERSION}"
