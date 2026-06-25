#!/usr/bin/env bash
# publish-update.sh — notarize + upload to self-hosted update server + update manifest
#
# Usage:
#   ./scripts/publish-update.sh                      # auto date-version (1.0.YYYYMMDD) then publish
#   ./scripts/publish-update.sh --test-update 1.0.7   # push fake xml for testing only (no build)
#   ./scripts/publish-update.sh --publish-only        # skip notarize/upload, just push manifest
# Prerequisites: ./mach build faster && ./mach package (unless using --test-update)
# Version is controlled via APP_VERSION in .env — format is 1.0.YYYYMMDD.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
ENV_FILE="$REPO_ROOT/.env"
VERSION_FILE="$REPO_ROOT/browser/config/version.txt"

source "$REPO_ROOT/scripts/lib/ui.sh"

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

TEST_VERSION=""
PUBLISH_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test-update) TEST_VERSION="$2"; shift 2 ;;
    --publish-only) PUBLISH_ONLY=true; shift ;;
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

# Auto date-version: 1.0.YYYYMMDD. If re-publishing on the same day, version stays the same.
if [[ -z "$TEST_VERSION" && "$PUBLISH_ONLY" != "true" ]]; then
  DATE_VERSION="1.0.$(date +%Y%m%d)"
  if [[ "$VERSION" != "$DATE_VERSION" ]]; then
    VERSION="$DATE_VERSION"
    sync_version "$VERSION"
    echo "Date build version: $VERSION"
    git -C "$REPO_ROOT" add \
      browser/config/version.txt \
      browser/config/version_display.txt \
      mozconfig \
      "browser/branding/w3ai/configure.sh" 2>/dev/null || true
    git -C "$REPO_ROOT" diff --cached --quiet || \
      git -C "$REPO_ROOT" commit -m "chore(release): date build $VERSION"
    git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION}"
    git -C "$REPO_ROOT" push origin HEAD --follow-tags --force-with-lease 2>/dev/null || \
      git -C "$REPO_ROOT" push origin HEAD
    git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
    echo "    Git tag v${VERSION} pushed."
  else
    echo "Re-publishing existing date build: $VERSION"
  fi
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
    -H "Accept: application/json" \
    -d "$BODY"
  echo ""
  echo "    update.xml now shows appVersion=$TEST_VERSION"
  exit 0
fi

ui_banner "TMRW Browser v${VERSION} — publishing update"

# ── --publish-only: skip notarize + upload, just call the publish endpoint ────
if [[ "$PUBLISH_ONLY" == "true" ]]; then
  echo "==> --publish-only: skipping notarize and upload (files already on server)"
  BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
  STATUS=$(curl -sf "$BASE_URL/api/status" || echo '{}')
  MAR_HASH=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('marHash',''))" 2>/dev/null || echo "")
  MAR_SIZE=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('marSize',0))" 2>/dev/null || echo "0")

  BODY="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"${MAR_HASH:-0}\",\"marSize\":${MAR_SIZE:-1}}"
  SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" | awk '{print $2}')"
  RESPONSE="$(curl -sf -X POST "$BASE_URL/api/publish" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -H "X-Signature: $SIG" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$BODY")"
  echo "    Published: $RESPONSE"
  echo "    Manifest: $BASE_URL/updates/update.xml"
  exit 0
fi

# Generate a monotonically-increasing BuildID for this release, then write it to
# application.ini BEFORE repackaging. nsXULAppInfo::GetAppBuildID() reads
# gAppData->buildID which is parsed from application.ini at startup — so the
# server buildID, the MAR's application.ini, and the running browser all agree.
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"

python3 - <<PYEOF
import re, pathlib
build_id = "$BUILD_ID"
version  = "$VERSION"
update_url = "https://tmrw-update.w3ai.io/updates/update.xml"
for path in [
    "$OBJ_DIR/build/application.ini",
    "$OBJ_DIR/dist/bin/application.ini",
]:
    p = pathlib.Path(path)
    if not p.exists(): continue
    txt = p.read_text()
    txt = re.sub(r'^BuildID=.*',  f'BuildID={build_id}', txt, flags=re.M)
    txt = re.sub(r'^Version=.*',  f'Version={version}',  txt, flags=re.M)
    # Point AppUpdate to our server, not Mozilla's AUS
    txt = re.sub(r'^URL=https://aus5\.mozilla\.org/.*', f'URL={update_url}', txt, flags=re.M)
    p.write_text(txt)
    print(f'  Patched {path}: Version={version} BuildID={build_id}')
PYEOF

# Repackage so the source DMG (used by notarize.sh) contains the patched application.ini.
# Without this, notarize.sh extracts the OLD source DMG and the DMG ships the wrong Version/BuildID.
ui_info "Repackaging with Version=${VERSION} BuildID=${BUILD_ID}..."
"$REPO_ROOT/mach" package >> /tmp/publish_pkg.log 2>&1 || { ui_fail "mach package failed"; exit 1; }
ui_ok "Repackaged"

# ── Step 1: Notarize ────────────────────────────────────────────
ui_step 1 5 "Notarizing build"
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/TMRW Browser.dmg"
if [[ ! -f "$SIGNED_DMG" ]]; then
  ui_fail "Notarized DMG not found at $SIGNED_DMG"
  exit 1
fi
DMG_SIZE="$(stat -f%z "$SIGNED_DMG")"
DMG_HASH="$(shasum -a 512 "$SIGNED_DMG" | awk '{print $1}')"
ui_ok "$(( DMG_SIZE / 1024 / 1024 )) MB — ${DMG_HASH:0:16}…"

# ── Step 2: Create MAR ────────────────────────────────────────────
ui_step 2 5 "Creating MAR update package"

# Ensure all updater binaries in the firefox package are patched before MAR creation.
ui_spinner_start "Patching updater binary in MAR source (fix XPC loop)…"
REPO_ROOT="$REPO_ROOT" python3 - <<'PYEOF'
import os
PATCH  = bytes([0xb8,0x01,0x00,0x00,0x00,0xc3,0x90,0x90,0x90,0x90])
OFFSET = 0xeb10
obj    = os.environ['REPO_ROOT'] + '/obj-x86_64-apple-darwin25.5.0'
targets = [
    obj + '/dist/firefox/TMRW Browser.app/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater',
    obj + '/dist/firefox/TMRW Browser.app/Contents/Library/LaunchServices/org.mozilla.updater',
    obj + '/dist/firefox/TMRW Browser.app/Contents/Resources/org.mozilla.updater',
    obj + '/dist/bin/org.mozilla.updater',
]
patched = 0
for path in targets:
    if not os.path.exists(path): continue
    with open(path, 'r+b') as f:
        f.seek(OFFSET)
        if f.read(2) == bytes([0xb8,0x01]): continue
        f.seek(OFFSET)
        f.write(PATCH)
        patched += 1
print(f'  Patched {patched} binaries')
PYEOF
ui_spinner_stop ok

ui_spinner_start "Packaging…"

MAR_TMPDIR="$(mktemp -d)"
MAR_OUTPUT="$MAR_TMPDIR/tmrw-${VERSION}.complete.mar"

(cd "$MAR_TMPDIR" && \
  MAR=/usr/local/bin/mar \
  MOZ_PRODUCT_VERSION="$VERSION" \
  MAR_CHANNEL_ID=default \
  XZ=/usr/local/bin/xz \
    "$REPO_ROOT/tools/update-packaging/make_full_update.sh" \
    "$MAR_OUTPUT" "$OBJ_DIR/dist/firefox/TMRW Browser.app" \
    2>&1 | grep -v "^        add\|^ add-if-not\|^      rmdir\|^     remove\|^mv: rename" || true
)

# make_full_update.sh writes output.mar in the CWD ($MAR_TMPDIR), not at argv[1]
# when the app path contains spaces (the `mv` inside the script fails silently).
[[ ! -f "$MAR_OUTPUT" && -f "$MAR_TMPDIR/output.mar" ]] && \
  mv "$MAR_TMPDIR/output.mar" "$MAR_OUTPUT"

if [[ ! -f "$MAR_OUTPUT" ]]; then
  ui_spinner_stop fail
  ui_fail "MAR creation failed"; rm -rf "$MAR_TMPDIR"; exit 1
fi
ui_spinner_stop ok
MAR_SIZE="$(stat -f%z "$MAR_OUTPUT")"
MAR_HASH="$(shasum -a 512 "$MAR_OUTPUT" | awk '{print $1}')"
ui_ok "$(( MAR_SIZE / 1024 / 1024 )) MB — ${MAR_HASH:0:16}…"

# ── Step 3: Upload MAR ────────────────────────────────────────────
ui_step 3 5 "Uploading MAR"
printf "\n"
mar_http=$(ui_upload_with_progress \
  "$BASE_URL/api/upload/mar" \
  "$MAR_OUTPUT" \
  "MAR  •  $(( MAR_SIZE / 1024 / 1024 )) MB" \
  "$VERSION")

if [[ "$mar_http" == "200" ]]; then
  rm -rf "$MAR_TMPDIR"
  ui_ok "Local MAR deleted"
else
  rm -rf "$MAR_TMPDIR"; exit 1
fi

# ── Step 4: Upload DMG ────────────────────────────────────────────
ui_step 4 5 "Uploading DMG"
printf "\n"
dmg_http=$(ui_upload_with_progress \
  "$BASE_URL/api/upload/dmg" \
  "$SIGNED_DMG" \
  "DMG  •  $(( DMG_SIZE / 1024 / 1024 )) MB" \
  "$VERSION")

if [[ "$dmg_http" == "200" ]]; then
  rm -f "$SIGNED_DMG"
  ui_ok "Local DMG deleted"
else
  ui_warn "DMG upload failed — MAR update will still work"
  ui_info "DMG kept at: $SIGNED_DMG"
fi

# ── Step 5: Publish manifest ────────────────────────────────────────────
ui_step 5 5 "Publishing update manifest"
ui_spinner_start "Publishing…"

BODY="{\"version\":\"$VERSION\",\"buildID\":\"$BUILD_ID\",\"marHash\":\"$MAR_HASH\",\"marSize\":$MAR_SIZE,\"dmgHash\":\"$DMG_HASH\",\"dmgSize\":$DMG_SIZE}"
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$PUBLISH_HMAC_SECRET" | awk '{print $2}')"

RESPONSE="$(curl -sf -X POST "$BASE_URL/api/publish" \
  -H "Authorization: Bearer $PUBLISH_SECRET" \
  -H "X-Signature: $SIG" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$BODY" 2>/dev/null)"

ui_spinner_stop ok
ui_ok "Manifest live"

printf "\n${UI_BOLD}${UI_GREEN}  Published v%s  (build %s)${UI_RESET}\n\n" "$VERSION" "$BUILD_ID"
printf "  ${UI_DIM}Manifest${UI_RESET}  %s/updates/update.xml\n" "$BASE_URL"
printf "  ${UI_DIM}MAR${UI_RESET}       %s/download/TMRW-Browser-v%s.complete.mar\n" "$BASE_URL" "$VERSION"
printf "  ${UI_DIM}DMG${UI_RESET}       %s/download/TMRW-Browser-v%s.dmg\n\n" "$BASE_URL" "$VERSION"
printf "  ${UI_DIM}Installed browsers update within 6 hours.${UI_RESET}\n"
printf "  ${UI_DIM}Trigger now: Help menu → Check for Updates${UI_RESET}\n\n"

git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (build ${BUILD_ID})" 2>/dev/null || true
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
printf "  ${UI_DIM}Git tag v%s pushed.${UI_RESET}\n\n" "$VERSION"
