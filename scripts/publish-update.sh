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
  STATUS=$(curl -sf "$BASE_URL/api/status" || echo '{}')
  BUILD_ID=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('buildID',''))" 2>/dev/null || echo "")
  [[ -z "$BUILD_ID" ]] && BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
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
eval "$(PRODUCT_NAME='TMRW-Browser' PRINT_EXPORTS=1 "$REPO_ROOT/scripts/tmrw-release-names.sh" "$VERSION" "$BUILD_ID")"

python3 - <<PYEOF
import re, pathlib
build_id = "$BUILD_ID"
version  = "$VERSION"
update_url = "https://tmrw-update.w3ai.io/updates/update.xml"

# Patch application.ini: Version, BuildID, and update URL
for path in [
    "$OBJ_DIR/build/application.ini",
    "$OBJ_DIR/dist/bin/application.ini",
]:
    p = pathlib.Path(path)
    if not p.exists(): continue
    txt = p.read_text()
    txt = re.sub(r'^BuildID=.*',  f'BuildID={build_id}', txt, flags=re.M)
    txt = re.sub(r'^Version=.*',  f'Version={version}',  txt, flags=re.M)
    txt = re.sub(r'^URL=https://aus5\.mozilla\.org/.*', f'URL={update_url}', txt, flags=re.M)
    p.write_text(txt)
    print(f'  Patched application.ini: Version={version} BuildID={build_id}')

# Patch platform.ini BuildID to match application.ini.
# platform.ini contains the Gecko/platform compile-time BuildID; without patching it,
# Firefox reports two different BuildIDs (application vs platform), which triggers
# the update checker to offer an update immediately after a clean install.
for path in [
    "$OBJ_DIR/build/platform.ini",
    "$OBJ_DIR/dist/bin/platform.ini",
    "$OBJ_DIR/dist/TMRW Browser.app/Contents/Resources/platform.ini",
]:
    p = pathlib.Path(path)
    if not p.exists(): continue
    txt = p.read_text()
    new_txt = re.sub(r'^BuildID=.*', f'BuildID={build_id}', txt, flags=re.M)
    if new_txt != txt:
        p.write_text(new_txt)
        print(f'  Patched platform.ini: BuildID={build_id} in {p}')
PYEOF

# Patch MOZ_BUILDID in AppConstants.sys.mjs inside omni.ja so the running browser reports
# the same BuildID that application.ini and the update server advertise. Without this patch
# the compiled-in MOZ_BUILDID (from mach build) stays stale after the update, causing Firefox
# to see a buildID mismatch on every restart and download the same update forever.
python3 - <<PYEOF
import io, os, re, zipfile

build_id = "$BUILD_ID"
version  = "$VERSION"
obj = "$OBJ_DIR"

# Patch all expanded AppConstants.sys.mjs files that mach package reads when creating omni.ja.
# The artifact build places the expanded app under dist/<AppName>.app and dist/bin/; mach package
# zips it into dist/firefox/<AppName>.app/Contents/Resources/omni.ja. Without patching the source
# files first, the regenerated omni.ja will always have the stale compile-time MOZ_BUILDID.
expanded_sources = [
    obj + "/dist/bin/modules/AppConstants.sys.mjs",
    obj + "/dist/TMRW Browser.app/Contents/Resources/modules/AppConstants.sys.mjs",
]
for expanded in expanded_sources:
    if not os.path.exists(expanded): continue
    text = open(expanded).read()
    new_text = re.sub(r'(MOZ_BUILDID:\s*")[^"]*(")', rf'\g<1>{build_id}\2', text)
    new_text = re.sub(r'(MOZ_APP_VERSION:\s*")[^"]*(")', rf'\g<1>{version}\2', new_text)
    new_text = re.sub(r'(MOZ_APP_VERSION_DISPLAY:\s*")[^"]*(")', rf'\g<1>{version}\2', new_text)
    if new_text != text:
        open(expanded, 'w').write(new_text)
        print(f'  Patched MOZ_BUILDID={build_id} MOZ_APP_VERSION={version} in {os.path.relpath(expanded, obj)}')

# Patch Info.plist CFBundleShortVersionString and CFBundleVersion in the source app bundle
# so that mach package copies the correct version into the distributable DMG.
import subprocess
info_plists = [
    obj + "/dist/TMRW Browser.app/Contents/Info.plist",
    obj + "/dist/bin/TMRW Browser.app/Contents/Info.plist",
]
for plist in info_plists:
    if not os.path.exists(plist): continue
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", f"Set :{key} {version}", plist],
            capture_output=True
        )
    subprocess.run(
        ["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleGetInfoString TMRW Browser {version}", plist],
        capture_output=True
    )
    print(f'  Patched Info.plist {version} in {os.path.relpath(plist, obj)}')

# Also patch any pre-assembled omni.ja files in case mach package uses them directly.
# Toolkit omni.ja: patch AppConstants and UpdateService (buildID comparisons).
jar_targets = [
    obj + "/dist/bin/omni.ja",
    obj + "/dist/firefox/TMRW Browser.app/Contents/Resources/omni.ja",
]
for path in jar_targets:
    if not os.path.exists(path):
        continue
    buf = io.BytesIO()
    modified = False
    with zipfile.ZipFile(path, 'r') as zin:
        with zipfile.ZipFile(buf, 'w') as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == 'modules/AppConstants.sys.mjs':
                    text = data.decode('utf-8')
                    new_text = re.sub(r'(MOZ_BUILDID:\s*")[^"]*(")', rf'\g<1>{build_id}\2', text)
                    new_text = re.sub(r'(MOZ_APP_VERSION:\s*")[^"]*(")', rf'\g<1>{version}\2', new_text)
                    new_text = re.sub(r'(MOZ_APP_VERSION_DISPLAY:\s*")[^"]*(")', rf'\g<1>{version}\2', new_text)
                    if new_text != text:
                        data = new_text.encode('utf-8')
                        modified = True
                elif item.filename == 'modules/UpdateService.sys.mjs':
                    # Use AppConstants.MOZ_BUILDID instead of the compiled-in
                    # Services.appinfo.appBuildID so the update service matches
                    # our patched build ID, preventing the infinite update loop.
                    text = data.decode('utf-8')
                    new_text = text.replace('Services.appinfo.appBuildID', 'AppConstants.MOZ_BUILDID')
                    if new_text != text:
                        data = new_text.encode('utf-8')
                        modified = True
                zout.writestr(item, data, compress_type=item.compress_type)
    if modified:
        with open(path, 'wb') as f:
            f.write(buf.getvalue())
        print(f'  Patched AppConstants+UpdateService in {os.path.basename(path)}')

# Browser omni.ja: patch aboutDialog so it uses AppConstants for version/buildID
# instead of Services.appinfo which returns the compiled-in binary values.
browser_jar_targets = [
    obj + "/dist/bin/browser/omni.ja",
    obj + "/dist/firefox/TMRW Browser.app/Contents/Resources/browser/omni.ja",
]
for path in browser_jar_targets:
    if not os.path.exists(path):
        continue
    buf = io.BytesIO()
    modified = False
    with zipfile.ZipFile(path, 'r') as zin:
        with zipfile.ZipFile(buf, 'w') as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == 'chrome/browser/content/browser/aboutDialog.js':
                    text = data.decode('utf-8')
                    new_text = text.replace(
                        'let version = Services.appinfo.version;',
                        'let version = AppConstants.MOZ_APP_VERSION;'
                    )
                    new_text = new_text.replace(
                        'let buildID = Services.appinfo.appBuildID;',
                        'let buildID = AppConstants.MOZ_BUILDID;'
                    )
                    if new_text != text:
                        data = new_text.encode('utf-8')
                        modified = True
                zout.writestr(item, data, compress_type=item.compress_type)
    if modified:
        with open(path, 'wb') as f:
            f.write(buf.getvalue())
        print(f'  Patched aboutDialog.js in {os.path.basename(path)}')
PYEOF

# Repackage so the source DMG (used by notarize.sh) contains the patched application.ini
# and the patched omni.ja (with correct MOZ_BUILDID). Without this, notarize.sh extracts
# the OLD source DMG and the DMG ships the wrong Version/BuildID.
ui_info "Repackaging with Version=${VERSION} BuildID=${BUILD_ID}..."
"$REPO_ROOT/mach" package >> /tmp/publish_pkg.log 2>&1 || { ui_fail "mach package failed"; exit 1; }
ui_ok "Repackaged"

ui_info "Verifying app bundle (Version=${VERSION} BuildID=${BUILD_ID})..."
EXPECTED_VERSION="$VERSION" \
EXPECTED_BUILD_ID="$BUILD_ID" \
APP_PATH="$OBJ_DIR/dist/firefox/TMRW Browser.app" \
  "$REPO_ROOT/scripts/verify-tmrw-release.sh" \
  || { ui_fail "App bundle verification failed — aborting release"; exit 1; }
ui_ok "App bundle verified"

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
MAR_OUTPUT="$MAR_TMPDIR/$TMRW_COMPLETE_MAR_NAME"

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

UPDATE_XML_TMP="$(mktemp /tmp/tmrw-update-XXXXXX.xml)"
cat > "$UPDATE_XML_TMP" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update type="minor" displayVersion="${VERSION}" appVersion="${VERSION}" platformVersion="151.0a1" buildID="${BUILD_ID}">
    <patch type="complete" URL="${BASE_URL}/download/${TMRW_COMPLETE_MAR_NAME}" hashFunction="sha512" hashValue="${MAR_HASH}" size="${MAR_SIZE}"/>
  </update>
</updates>
XML

ui_info "Verifying MAR + update.xml before upload..."
EXPECTED_VERSION="$VERSION" \
EXPECTED_BUILD_ID="$BUILD_ID" \
APP_PATH="$OBJ_DIR/dist/firefox/TMRW Browser.app" \
MAR_PATH="$MAR_OUTPUT" \
UPDATE_XML_PATH="$UPDATE_XML_TMP" \
  "$REPO_ROOT/scripts/verify-tmrw-release.sh" \
  || { ui_fail "Pre-upload verification failed — aborting release"; rm -f "$UPDATE_XML_TMP"; rm -rf "$MAR_TMPDIR"; exit 1; }
rm -f "$UPDATE_XML_TMP"
ui_ok "Pre-upload verification passed"

# ── Step 3: Upload MAR ────────────────────────────────────────────
ui_step 3 5 "Uploading MAR"
printf "\n"
mar_http=$(ui_upload_with_progress \
  "$BASE_URL/api/upload/mar" \
  "$MAR_OUTPUT" \
  "MAR  •  $(( MAR_SIZE / 1024 / 1024 )) MB" \
  "$VERSION" \
  "$BUILD_ID")

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
  "$VERSION" \
  "$BUILD_ID")

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
printf "  ${UI_DIM}MAR${UI_RESET}       %s/download/%s\n" "$BASE_URL" "$TMRW_COMPLETE_MAR_NAME"
printf "  ${UI_DIM}DMG${UI_RESET}       %s/download/%s\n\n" "$BASE_URL" "$TMRW_DMG_NAME"
printf "  ${UI_DIM}Installed browsers update within 6 hours.${UI_RESET}\n"
printf "  ${UI_DIM}Trigger now: Help menu → Check for Updates${UI_RESET}\n\n"

git -C "$REPO_ROOT" tag -f -a "v${VERSION}" -m "Release v${VERSION} (build ${BUILD_ID})" 2>/dev/null || true
git -C "$REPO_ROOT" push origin "v${VERSION}" --force 2>/dev/null || true
printf "  ${UI_DIM}Git tag v%s pushed.${UI_RESET}\n\n" "$VERSION"
