#!/usr/bin/env bash
# upload-release.sh — upload existing notarized DMG + create & upload MAR + publish manifest
#
# Run this after notarize.sh has produced a signed DMG, OR after manually placing
# a notarized DMG at:  obj-x86_64-apple-darwin25.5.0/dist/TMRW.dmg
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

source "$REPO_ROOT/scripts/lib/ui.sh"

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
  [[ -z "${!var:-}" ]] && { ui_fail "$var not set in .env"; exit 1; }
done

BASE_URL="${UPDATE_SERVER_URL}"

# ── Detect version from built app, fall back to .env ──────────────────────────
APP_INI="$OBJ_DIR/dist/firefox/TMRW.app/Contents/Resources/application.ini"
VERSION=""
[[ -f "$APP_INI" ]] && VERSION="$(grep "^Version=" "$APP_INI" | cut -d= -f2)"
[[ -z "$VERSION" ]] && VERSION="${APP_VERSION:-1.0.0}"

BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
SIGNED_DMG="$OBJ_DIR/dist/TMRW.dmg"
MAR_TMPDIR=""
MAR_OUTPUT=""
MAR_SIZE=0 ; MAR_HASH=""
DMG_SIZE=0 ; DMG_HASH=""

ui_banner "TMRW v${VERSION} — upload release"

# ── Step 1: Validate DMG ──────────────────────────────────────────────────────
if [[ "$MAR_ONLY" != "true" ]]; then
  ui_step 1 4 "Checking notarized DMG"
  if [[ ! -f "$SIGNED_DMG" ]]; then
    ui_fail "Notarized DMG not found at: $SIGNED_DMG"
    ui_info "Run ./scripts/notarize.sh first, or place a signed DMG there manually."
    exit 1
  fi
  DMG_SIZE="$(stat -f%z "$SIGNED_DMG")"
  DMG_HASH="$(shasum -a 512 "$SIGNED_DMG" | awk '{print $1}')"
  ui_ok "$(( DMG_SIZE / 1024 / 1024 )) MB — ${DMG_HASH:0:16}…"
fi

# ── Step 2: Create MAR ────────────────────────────────────────────────────────
if [[ "$DMG_ONLY" != "true" ]]; then
  ui_step 2 4 "Creating MAR update package"
  PKG_APP="$OBJ_DIR/dist/firefox/TMRW.app"
  if [[ ! -d "$PKG_APP" ]]; then
    ui_fail "Packaged app not found: $PKG_APP"
    ui_info "Run: ./mach build faster && ./mach package"
    exit 1
  fi

  ui_spinner_start "Packaging…"
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
      "$MAR_OUTPUT" "$APP_LINK" \
      2>&1 | grep -v "^        add\|^ add-if-not\|^      rmdir\|^     remove" || true
  )

  [[ ! -f "$MAR_OUTPUT" && -f "$MAR_TMPDIR/output.mar" ]] && \
    mv "$MAR_TMPDIR/output.mar" "$MAR_OUTPUT"

  if [[ ! -f "$MAR_OUTPUT" ]]; then
    ui_spinner_stop fail
    ui_fail "MAR creation failed"
    rm -rf "$MAR_TMPDIR"
    exit 1
  fi

  ui_spinner_stop ok
  MAR_SIZE="$(stat -f%z "$MAR_OUTPUT")"
  MAR_HASH="$(shasum -a 512 "$MAR_OUTPUT" | awk '{print $1}')"
  ui_ok "$(( MAR_SIZE / 1024 / 1024 )) MB — ${MAR_HASH:0:16}…"
fi

# ── Step 3: Upload ────────────────────────────────────────────────────────────
ui_step 3 4 "Uploading to update server"

if [[ "$DMG_ONLY" != "true" && -n "$MAR_OUTPUT" ]]; then
  printf "\n"
  http_code=$(ui_upload_with_progress \
    "$BASE_URL/api/upload/mar" \
    "$MAR_OUTPUT" \
    "MAR  •  $(( MAR_SIZE / 1024 / 1024 )) MB" \
    "$VERSION")

  if [[ "$http_code" == "200" ]]; then
    rm -rf "$MAR_TMPDIR" && MAR_TMPDIR=""
    ui_ok "Local MAR deleted"
  else
    rm -rf "$MAR_TMPDIR"
    exit 1
  fi
fi

if [[ "$MAR_ONLY" != "true" ]]; then
  printf "\n"
  http_code=$(ui_upload_with_progress \
    "$BASE_URL/api/upload/dmg" \
    "$SIGNED_DMG" \
    "DMG  •  $(( DMG_SIZE / 1024 / 1024 )) MB" \
    "$VERSION") && dmg_ok=true || dmg_ok=false

  if $dmg_ok; then
    rm -f "$SIGNED_DMG"
    ui_ok "Local DMG deleted"
  else
    ui_warn "DMG upload failed — kept at: $SIGNED_DMG"
    ui_info "MAR update will still work for existing installs."
  fi
fi

# ── Step 4: Publish manifest ──────────────────────────────────────────────────
ui_step 4 4 "Publishing update manifest"

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

ui_spinner_start "Publishing…"

BODY="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"${MAR_HASH:-0}\",\"marSize\":${MAR_SIZE:-1},\"dmgHash\":\"${DMG_HASH:-0}\",\"dmgSize\":${DMG_SIZE:-1}}"
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" | awk '{print $2}')"

RESPONSE="$(curl -sf -X POST "$BASE_URL/api/publish" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -H "X-Signature: $SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>/dev/null)"

ui_spinner_stop ok
ui_ok "Manifest live"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${UI_BOLD}${UI_GREEN}  Published v%s  (build %s)${UI_RESET}\n\n" "$VERSION" "$BUILD_ID"
printf "  ${UI_DIM}Manifest${UI_RESET}  %s/updates/update.xml\n" "$BASE_URL"
printf "  ${UI_DIM}MAR${UI_RESET}       %s/download/TMRW-Browser-v%s.complete.mar\n" "$BASE_URL" "$VERSION"
printf "  ${UI_DIM}DMG${UI_RESET}       %s/download/TMRW-Browser-v%s.dmg\n\n" "$BASE_URL" "$VERSION"
printf "  ${UI_DIM}Installed browsers update within 6 hours.${UI_RESET}\n"
printf "  ${UI_DIM}Trigger now: Help menu → Check for Updates${UI_RESET}\n\n"

git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (build ${BUILD_ID})" 2>/dev/null || true
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
printf "  ${UI_DIM}Git tag v%s pushed.${UI_RESET}\n\n" "$VERSION"
