#!/usr/bin/env bash
# verify-release-build.sh — validate that DMG, MAR, update.xml, and app bundle all
# report the same version/buildID before a release is considered complete.
#
# Usage:
#   EXPECTED_VERSION=1.0.20260625 \
#   APP_PATH="/path/to/TMRW.app" \
#   DMG_PATH="/path/to/TMRW-Browser-v1.0.20260625.dmg" \
#   MAR_PATH="/path/to/TMRW-Browser-v1.0.20260625.complete.mar" \
#   UPDATE_XML_URL="https://tmrw-update.w3ai.io/updates/update.xml" \
#     ./scripts/verify-release-build.sh
#
# All variables can also be passed as positional arguments:
#   ./scripts/verify-release-build.sh <version> <app_path> [dmg_path] [mar_path] [update_xml_url]

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/ui.sh" 2>/dev/null || true

PASS=0
FAIL=0

ok()   { echo "  [PASS] $*"; (( PASS++ )) || true; }
fail() { echo "  [FAIL] $*"; (( FAIL++ )) || true; }
info() { echo "  [INFO] $*"; }

check_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    ok "$label: $got"
  else
    fail "$label: expected '$want', got '$got'"
  fi
}

# ── Resolve arguments ──────────────────────────────────────────────────────────
EXPECTED_VERSION="${EXPECTED_VERSION:-${1:-}}"
APP_PATH="${APP_PATH:-${2:-}}"
DMG_PATH="${DMG_PATH:-${3:-}}"
MAR_PATH="${MAR_PATH:-${4:-}}"
UPDATE_XML_URL="${UPDATE_XML_URL:-${5:-https://tmrw-update.w3ai.io/updates/update.xml}}"

if [[ -z "$EXPECTED_VERSION" ]]; then
  # Fall back to .env
  ENV_FILE="$REPO_ROOT/.env"
  if [[ -f "$ENV_FILE" ]]; then
    EXPECTED_VERSION="$(grep '^APP_VERSION=' "$ENV_FILE" | head -1 | cut -d= -f2 | tr -d '"' )"
  fi
fi
if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "ERROR: EXPECTED_VERSION not set. Pass it as env var or first argument."
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  # Default to built packaged app
  APP_PATH="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0/dist/firefox/TMRW.app"
fi

echo ""
echo "=== TMRW Release Verification ==="
echo "  Expected version : $EXPECTED_VERSION"
echo "  App bundle       : $APP_PATH"
[[ -n "$DMG_PATH" ]] && echo "  DMG              : $DMG_PATH"
[[ -n "$MAR_PATH" ]] && echo "  MAR              : $MAR_PATH"
echo "  Update XML URL   : $UPDATE_XML_URL"
echo ""

# ── 1. App bundle ─────────────────────────────────────────────────────────────
echo "── App Bundle ──────────────────────────────────────────────────────"
if [[ ! -d "$APP_PATH" ]]; then
  fail "App bundle does not exist: $APP_PATH"
else
  ok "App bundle exists"

  APP_INI="$APP_PATH/Contents/Resources/application.ini"
  if [[ -f "$APP_INI" ]]; then
    INI_VERSION="$(grep '^Version=' "$APP_INI" | cut -d= -f2)"
    INI_BUILDID="$(grep '^BuildID=' "$APP_INI" | cut -d= -f2)"
    check_eq "application.ini Version" "$INI_VERSION" "$EXPECTED_VERSION"
    info "application.ini BuildID: $INI_BUILDID"
  else
    fail "application.ini not found at $APP_INI"
    INI_BUILDID=""
  fi

  PLATFORM_INI="$APP_PATH/Contents/Resources/platform.ini"
  if [[ -f "$PLATFORM_INI" ]]; then
    PLAT_BUILDID="$(grep '^BuildID=' "$PLATFORM_INI" | cut -d= -f2)"
    if [[ -n "$INI_BUILDID" ]]; then
      check_eq "platform.ini BuildID matches application.ini BuildID" "$PLAT_BUILDID" "$INI_BUILDID"
    else
      info "platform.ini BuildID: $PLAT_BUILDID"
    fi
  else
    fail "platform.ini not found at $PLATFORM_INI"
  fi

  INFO_PLIST="$APP_PATH/Contents/Info.plist"
  if [[ -f "$INFO_PLIST" ]]; then
    PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo '')"
    check_eq "Info.plist CFBundleShortVersionString matches application.ini Version" "$PLIST_VERSION" "$INI_VERSION"
  else
    fail "Info.plist not found"
  fi

  OMNI_JA="$APP_PATH/Contents/Resources/omni.ja"
  if [[ -f "$OMNI_JA" ]]; then
    APPC_VERSION="$(unzip -p "$OMNI_JA" modules/AppConstants.sys.mjs 2>/dev/null | grep 'MOZ_APP_VERSION:' | sed "s/.*\"\([^\"]*\)\".*/\1/")"
    APPC_BUILDID="$(unzip -p "$OMNI_JA" modules/AppConstants.sys.mjs 2>/dev/null | grep 'MOZ_BUILDID:' | sed "s/.*\"\([^\"]*\)\".*/\1/")"
    check_eq "omni.ja AppConstants MOZ_APP_VERSION matches application.ini Version" "$APPC_VERSION" "$INI_VERSION"
    if [[ -n "$INI_BUILDID" ]]; then
      check_eq "omni.ja AppConstants MOZ_BUILDID matches application.ini BuildID" "$APPC_BUILDID" "$INI_BUILDID"
    else
      info "omni.ja AppConstants MOZ_BUILDID: $APPC_BUILDID"
    fi
  else
    fail "omni.ja not found at $OMNI_JA"
  fi
fi
echo ""

# ── 2. DMG ────────────────────────────────────────────────────────────────────
if [[ -n "$DMG_PATH" ]]; then
  echo "── DMG ─────────────────────────────────────────────────────────────"
  if [[ ! -f "$DMG_PATH" ]]; then
    fail "DMG not found: $DMG_PATH"
  else
    ok "DMG exists ($(( $(stat -f%z "$DMG_PATH") / 1024 / 1024 )) MB)"
    MOUNT_POINT="/tmp/tmrw-verify-dmg-$$"
    if hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_POINT" -quiet 2>/dev/null; then
      DMG_APP="$MOUNT_POINT/TMRW.app"
      if [[ -d "$DMG_APP" ]]; then
        DMG_INI="$DMG_APP/Contents/Resources/application.ini"
        DMG_VERSION="$(grep '^Version=' "$DMG_INI" 2>/dev/null | cut -d= -f2)"
        DMG_BUILDID="$(grep '^BuildID=' "$DMG_INI" 2>/dev/null | cut -d= -f2)"
        check_eq "DMG application.ini Version" "$DMG_VERSION" "$EXPECTED_VERSION"
        info "DMG application.ini BuildID: $DMG_BUILDID"

        DMG_OMNI="$DMG_APP/Contents/Resources/omni.ja"
        if [[ -f "$DMG_OMNI" ]]; then
          DMG_APPC_V="$(unzip -p "$DMG_OMNI" modules/AppConstants.sys.mjs 2>/dev/null | grep 'MOZ_APP_VERSION:' | sed "s/.*\"\([^\"]*\)\".*/\1/")"
          DMG_APPC_B="$(unzip -p "$DMG_OMNI" modules/AppConstants.sys.mjs 2>/dev/null | grep 'MOZ_BUILDID:' | sed "s/.*\"\([^\"]*\)\".*/\1/")"
          check_eq "DMG omni.ja AppConstants MOZ_APP_VERSION" "$DMG_APPC_V" "$EXPECTED_VERSION"
          [[ -n "$DMG_BUILDID" ]] && check_eq "DMG omni.ja MOZ_BUILDID matches application.ini BuildID" "$DMG_APPC_B" "$DMG_BUILDID"
        fi

        # Check for stale version
        if echo "$DMG_VERSION $DMG_APPC_V" | grep -q "20260624"; then
          fail "DMG contains stale version 1.0.20260624!"
        fi
      else
        fail "TMRW.app not found inside DMG"
      fi
      hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    else
      fail "Could not mount DMG: $DMG_PATH"
    fi
    rm -rf "$MOUNT_POINT" 2>/dev/null || true
  fi
  echo ""
fi

# ── 3. MAR ────────────────────────────────────────────────────────────────────
MAR_HASH=""
MAR_SIZE=0
if [[ -n "$MAR_PATH" ]]; then
  echo "── MAR ─────────────────────────────────────────────────────────────"
  if [[ ! -f "$MAR_PATH" ]]; then
    fail "MAR not found: $MAR_PATH"
  else
    MAR_SIZE="$(stat -f%z "$MAR_PATH")"
    MAR_HASH="$(shasum -a 512 "$MAR_PATH" | awk '{print $1}')"
    ok "MAR exists ($(( MAR_SIZE / 1024 / 1024 )) MB)"
    info "MAR SHA512: ${MAR_HASH:0:32}…"

    # Check application.ini inside MAR
    MAR_TMP="$(mktemp -d)"
    if /usr/local/bin/mar -C "$MAR_TMP" -x "$MAR_PATH" Contents/Resources/application.ini 2>/dev/null; then
      MAR_INI_VERSION="$(xzcat "$MAR_TMP/Contents/Resources/application.ini" 2>/dev/null | grep '^Version=' | cut -d= -f2)"
      MAR_INI_BUILDID="$(xzcat "$MAR_TMP/Contents/Resources/application.ini" 2>/dev/null | grep '^BuildID=' | cut -d= -f2)"
      check_eq "MAR application.ini Version" "$MAR_INI_VERSION" "$EXPECTED_VERSION"
      info "MAR application.ini BuildID: $MAR_INI_BUILDID"
    fi
    rm -rf "$MAR_TMP"
  fi
  echo ""
fi

# ── 4. Update XML ─────────────────────────────────────────────────────────────
echo "── Update XML ──────────────────────────────────────────────────────"
if XML="$(curl -sf --max-time 15 "$UPDATE_XML_URL" 2>/dev/null)"; then
  ok "Update XML fetched from $UPDATE_XML_URL"

  XML_VERSION="$(echo "$XML" | grep -o 'appVersion="[^"]*"' | head -1 | cut -d'"' -f2)"
  XML_BUILDID="$(echo "$XML" | grep -o 'buildID="[^"]*"' | head -1 | cut -d'"' -f2)"
  XML_HASH="$(echo "$XML" | grep -o 'hashValue="[^"]*"' | head -1 | cut -d'"' -f2)"
  XML_SIZE="$(echo "$XML" | grep -o 'size="[^"]*"' | head -1 | cut -d'"' -f2)"
  XML_URL="$(echo "$XML" | grep -o 'URL="[^"]*"' | head -1 | cut -d'"' -f2)"
  XML_HASH_FN="$(echo "$XML" | grep -o 'hashFunction="[^"]*"' | head -1 | cut -d'"' -f2)"

  check_eq "update.xml appVersion matches application.ini Version" "$XML_VERSION" "$INI_VERSION"
  if [[ -n "$INI_BUILDID" ]]; then
    check_eq "update.xml buildID matches application.ini BuildID" "$XML_BUILDID" "$INI_BUILDID"
  else
    info "update.xml buildID: $XML_BUILDID"
  fi
  info "update.xml patch URL: $XML_URL"
  info "update.xml hashFunction: $XML_HASH_FN"

  if [[ -n "$MAR_PATH" && -f "$MAR_PATH" ]]; then
    check_eq "update.xml size matches MAR file size" "$XML_SIZE" "$MAR_SIZE"
    check_eq "update.xml SHA512 matches MAR file hash" "$XML_HASH" "$MAR_HASH"
  elif [[ -n "$XML_URL" ]]; then
    # Verify the MAR on the server
    SERVER_SIZE="$(curl -sI --max-time 15 "$XML_URL" 2>/dev/null | grep -i 'content-length:' | tr -d '\r' | awk '{print $2}')"
    if [[ -n "$SERVER_SIZE" ]]; then
      check_eq "update.xml size matches server MAR Content-Length" "$XML_SIZE" "$SERVER_SIZE"
    else
      info "Could not check server MAR size (HEAD request failed)"
    fi
  fi
else
  fail "Could not fetch update XML from $UPDATE_XML_URL"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════════"
echo "  Passed: $PASS   Failed: $FAIL"
if [[ $FAIL -eq 0 ]]; then
  echo "  RESULT: ALL CHECKS PASSED — release is valid"
  echo "═══════════════════════════════════════════════════════════════════"
  exit 0
else
  echo "  RESULT: $FAIL CHECK(S) FAILED — DO NOT RELEASE"
  echo "═══════════════════════════════════════════════════════════════════"
  exit 1
fi
