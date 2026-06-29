#!/usr/bin/env bash
set -euo pipefail

# TMRW Browser release verification gate.
# This script intentionally does not change Gecko/Firefox updater behavior.
# It verifies that the build artifacts feed Gecko's updater one consistent
# Version + BuildID across the app bundle, DMG, MAR metadata in update.xml,
# and live/local update XML.
#
# Required env:
#   EXPECTED_VERSION="1.0.20260629"
#   EXPECTED_BUILD_ID="20260629064709"
#   APP_PATH="/path/to/TMRW Browser.app"
#
# Optional env:
#   DMG_PATH="/path/to/TMRW-Browser-v1.0.20260629-build20260629064709.dmg"
#   MAR_PATH="/path/to/TMRW-Browser-v1.0.20260629-build20260629064709.complete.mar"
#   UPDATE_XML_PATH="/path/to/update.xml"
#   UPDATE_XML_URL="https://tmrw-update.w3ai.io/updates/update.xml"
#   OLD_VERSION="1.0.20260628"
#   SKIP_DMG_VERIFY=1
#   SKIP_OMNI_VERIFY=1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

note() {
  echo "==> $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

read_ini_value() {
  local file="$1"
  local key="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file"
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

sha512_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 512 "$file" | awk '{print $1}'
  elif command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$file" | awk '{print $1}'
  else
    fail "Neither shasum nor sha512sum is available"
  fi
}

file_size() {
  local file="$1"
  if stat -f%z "$file" >/dev/null 2>&1; then
    stat -f%z "$file"
  else
    stat -c%s "$file"
  fi
}

xml_attr() {
  local xml="$1"
  local tag="$2"
  local attr="$3"
  awk -v tag="$tag" -v attr="$attr" '
    $0 ~ "<" tag {
      n = split($0, a, attr "=\"")
      if (n > 1) {
        split(a[2], b, "\"")
        print b[1]
        exit
      }
    }
  ' "$xml"
}

verify_app_bundle() {
  local app="$1"
  local label="$2"

  note "Verifying app bundle: $label"
  [ -d "$app" ] || fail "$label app bundle not found: $app"

  local app_ini="$app/Contents/Resources/application.ini"
  local platform_ini="$app/Contents/Resources/platform.ini"
  local plist="$app/Contents/Info.plist"
  local omni="$app/Contents/Resources/omni.ja"

  [ -f "$app_ini" ] || fail "$label missing application.ini: $app_ini"
  [ -f "$platform_ini" ] || fail "$label missing platform.ini: $platform_ini"
  [ -f "$plist" ] || fail "$label missing Info.plist: $plist"

  local app_version app_build platform_build plist_short plist_bundle
  app_version="$(read_ini_value "$app_ini" Version)"
  app_build="$(read_ini_value "$app_ini" BuildID)"
  platform_build="$(read_ini_value "$platform_ini" BuildID)"
  plist_short="$(plist_value "$plist" CFBundleShortVersionString)"
  plist_bundle="$(plist_value "$plist" CFBundleVersion)"

  echo "application.ini Version: $app_version"
  echo "application.ini BuildID: $app_build"
  echo "platform.ini BuildID:    $platform_build"
  echo "Info.plist short:        $plist_short"
  echo "Info.plist bundle:       $plist_bundle"

  [ "$app_version" = "$EXPECTED_VERSION" ] || fail "$label application.ini Version mismatch: $app_version != $EXPECTED_VERSION"
  [ "$app_build" = "$EXPECTED_BUILD_ID" ] || fail "$label application.ini BuildID mismatch: $app_build != $EXPECTED_BUILD_ID"
  [ "$platform_build" = "$EXPECTED_BUILD_ID" ] || fail "$label platform.ini BuildID mismatch: $platform_build != $EXPECTED_BUILD_ID"
  [ "$app_build" = "$platform_build" ] || fail "$label application.ini BuildID != platform.ini BuildID"
  [ "$plist_short" = "$EXPECTED_VERSION" ] || fail "$label CFBundleShortVersionString mismatch: $plist_short != $EXPECTED_VERSION"
  [ "$plist_bundle" = "$EXPECTED_VERSION" ] || fail "$label CFBundleVersion mismatch: $plist_bundle != $EXPECTED_VERSION"

  if [ -n "${OLD_VERSION:-}" ]; then
    if grep -R --binary-files=without-match -n "$OLD_VERSION" "$app/Contents/Resources/application.ini" "$app/Contents/Resources/platform.ini" "$app/Contents/Info.plist" >/dev/null 2>&1; then
      fail "$label contains OLD_VERSION in core metadata: $OLD_VERSION"
    fi
  fi

  if [ "${SKIP_OMNI_VERIFY:-0}" != "1" ] && [ -f "$omni" ]; then
    need_cmd unzip
    local omni_text
    omni_text="$(mktemp)"
    unzip -p "$omni" 'modules/AppConstants*.js*' 'modules/AppConstants*.mjs' 2>/dev/null > "$omni_text" || true

    if [ -s "$omni_text" ]; then
      grep -q "$EXPECTED_VERSION" "$omni_text" || fail "$label omni.ja AppConstants does not contain EXPECTED_VERSION $EXPECTED_VERSION"
      grep -q "$EXPECTED_BUILD_ID" "$omni_text" || fail "$label omni.ja AppConstants does not contain EXPECTED_BUILD_ID $EXPECTED_BUILD_ID"
      if [ -n "${OLD_VERSION:-}" ] && grep -q "$OLD_VERSION" "$omni_text"; then
        fail "$label omni.ja AppConstants still contains OLD_VERSION $OLD_VERSION"
      fi
    else
      echo "WARN: Could not read AppConstants from omni.ja; set SKIP_OMNI_VERIFY=1 to silence this warning."
    fi
    rm -f "$omni_text"
  fi
}

verify_update_xml() {
  local xml="$1"
  note "Verifying update XML: $xml"
  [ -f "$xml" ] || fail "update XML not found: $xml"

  local app_version display_version build_id patch_type patch_url hash_function hash_value patch_size
  app_version="$(xml_attr "$xml" update appVersion)"
  display_version="$(xml_attr "$xml" update displayVersion)"
  build_id="$(xml_attr "$xml" update buildID)"
  patch_type="$(xml_attr "$xml" patch type)"
  patch_url="$(xml_attr "$xml" patch URL)"
  hash_function="$(xml_attr "$xml" patch hashFunction)"
  hash_value="$(xml_attr "$xml" patch hashValue)"
  patch_size="$(xml_attr "$xml" patch size)"

  echo "update appVersion:     $app_version"
  echo "update displayVersion: $display_version"
  echo "update buildID:        $build_id"
  echo "patch type:            $patch_type"
  echo "patch URL:             $patch_url"
  echo "patch hashFunction:    $hash_function"
  echo "patch hashValue:       $hash_value"
  echo "patch size:            $patch_size"

  [ "$app_version" = "$EXPECTED_VERSION" ] || fail "update.xml appVersion mismatch: $app_version != $EXPECTED_VERSION"
  [ "$display_version" = "$EXPECTED_VERSION" ] || fail "update.xml displayVersion mismatch: $display_version != $EXPECTED_VERSION"
  [ "$build_id" = "$EXPECTED_BUILD_ID" ] || fail "update.xml buildID mismatch: $build_id != $EXPECTED_BUILD_ID"
  [ "$patch_type" = "complete" ] || fail "update.xml must use complete MAR while updater is being stabilized; got: $patch_type"
  [ "$hash_function" = "sha512" ] || fail "update.xml hashFunction must be sha512; got: $hash_function"
  [ -n "$patch_url" ] || fail "update.xml patch URL is empty"
  [ -n "$hash_value" ] || fail "update.xml hashValue is empty"
  [ -n "$patch_size" ] || fail "update.xml patch size is empty"

  if [ -n "${MAR_PATH:-}" ]; then
    [ -f "$MAR_PATH" ] || fail "MAR_PATH not found: $MAR_PATH"
    local actual_hash actual_size
    actual_hash="$(sha512_file "$MAR_PATH")"
    actual_size="$(file_size "$MAR_PATH")"
    echo "actual MAR sha512:     $actual_hash"
    echo "actual MAR size:       $actual_size"
    [ "$hash_value" = "$actual_hash" ] || fail "update.xml hashValue does not match MAR sha512"
    [ "$patch_size" = "$actual_size" ] || fail "update.xml size does not match MAR size"
  fi

  if [ -n "${OLD_VERSION:-}" ] && grep -q "$OLD_VERSION" "$xml"; then
    fail "update.xml still contains OLD_VERSION: $OLD_VERSION"
  fi
}

verify_dmg() {
  local dmg="$1"
  [ "${SKIP_DMG_VERIFY:-0}" = "1" ] && return 0
  [ -f "$dmg" ] || fail "DMG not found: $dmg"
  need_cmd hdiutil

  note "Mounting and verifying DMG: $dmg"
  local mount_dir
  mount_dir="$(mktemp -d /tmp/tmrw-dmg.XXXXXX)"

  hdiutil attach "$dmg" -mountpoint "$mount_dir" -nobrowse -quiet
  trap 'hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true; rm -rf "$mount_dir"' RETURN

  local dmg_app
  dmg_app="$(find "$mount_dir" -maxdepth 2 -name '*.app' -type d | head -1)"
  [ -n "$dmg_app" ] || fail "No .app bundle found inside DMG"
  verify_app_bundle "$dmg_app" "DMG"

  hdiutil detach "$mount_dir" -quiet
  trap - RETURN
  rm -rf "$mount_dir"
}

main() {
  [ -n "${EXPECTED_VERSION:-}" ] || fail "EXPECTED_VERSION is required"
  [ -n "${EXPECTED_BUILD_ID:-}" ] || fail "EXPECTED_BUILD_ID is required"
  [ -n "${APP_PATH:-}" ] || fail "APP_PATH is required"

  verify_app_bundle "$APP_PATH" "APP_PATH"

  if [ -n "${DMG_PATH:-}" ]; then
    verify_dmg "$DMG_PATH"
  fi

  local xml_tmp=""
  if [ -n "${UPDATE_XML_URL:-}" ]; then
    need_cmd curl
    xml_tmp="$(mktemp)"
    note "Downloading live update XML: $UPDATE_XML_URL"
    curl -fsSL "$UPDATE_XML_URL" -o "$xml_tmp"
    UPDATE_XML_PATH="$xml_tmp"
  fi

  if [ -n "${UPDATE_XML_PATH:-}" ]; then
    verify_update_xml "$UPDATE_XML_PATH"
  fi

  rm -f "$xml_tmp"
  note "TMRW release verification passed."
}

main "$@"
