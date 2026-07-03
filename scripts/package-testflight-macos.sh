#!/usr/bin/env bash
set -euo pipefail

# Package TMRW.app for Mac TestFlight/App Store Connect.
#
# This script fixes the exact Transporter/TestFlight class of issue where
# Contents/MacOS/plugin-container.app is signed with an application identifier
# but has no embedded provisioning profile. Firefox/Gecko uses plugin-container
# for content processes, so if this nested app is not signed/profiled correctly,
# web content can fail to load and chrome JS will report remoteTab/messageManager
# null errors.
#
# Required environment:
#   APP_PATH=/path/to/TMRW.app
#   OUT_DIR=/path/to/output
#   APP_SIGN_IDENTITY="3rd Party Mac Developer Application: Plato Technologies inc. (TEAMID)"
#   INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Plato Technologies inc. (TEAMID)"
#   MAIN_PROVISION_PROFILE=/path/to/main-app.provisionprofile
#   PLUGIN_CONTAINER_PROVISION_PROFILE=/path/to/plugin-container.provisionprofile
#
# Optional environment:
#   VERSION=1.2.1
#   MAIN_ENTITLEMENTS=build/macos/testflight/TMRW.entitlements
#   PLUGIN_ENTITLEMENTS=build/macos/testflight/plugin-container.entitlements
#   PLUGIN_BUNDLE_ID=com.tmrw.w3ai.plugin-container
#   PKG_NAME=TMRW-1.2.1-TestFlight.pkg

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

note() {
  echo "==> $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

plist_set() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

copy_profile() {
  local profile="$1"
  local bundle="$2"
  [ -f "$profile" ] || fail "Provisioning profile not found: $profile"
  [ -d "$bundle" ] || fail "Bundle not found: $bundle"
  cp "$profile" "$bundle/Contents/embedded.provisionprofile"
}

sign_bundle() {
  local bundle="$1"
  local entitlements="$2"
  [ -d "$bundle" ] || fail "Bundle not found: $bundle"
  [ -f "$entitlements" ] || fail "Entitlements not found: $entitlements"
  codesign --force --options runtime --timestamp --entitlements "$entitlements" --sign "$APP_SIGN_IDENTITY" "$bundle"
}

verify_bundle_profile() {
  local bundle="$1"
  local label="$2"
  [ -f "$bundle/Contents/embedded.provisionprofile" ] || fail "$label is missing embedded.provisionprofile"
  codesign --verify --deep --strict --verbose=2 "$bundle"
  codesign -dv --verbose=4 "$bundle" 2>&1 | sed "s/^/$label codesign: /"
}

main() {
  need_cmd codesign
  need_cmd productbuild
  need_cmd pkgutil
  need_cmd xcrun

  APP_PATH="${APP_PATH:-}"
  OUT_DIR="${OUT_DIR:-}"
  VERSION="${VERSION:-1.2.1}"
  MAIN_ENTITLEMENTS="${MAIN_ENTITLEMENTS:-build/macos/testflight/TMRW.entitlements}"
  PLUGIN_ENTITLEMENTS="${PLUGIN_ENTITLEMENTS:-build/macos/testflight/plugin-container.entitlements}"
  PLUGIN_BUNDLE_ID="${PLUGIN_BUNDLE_ID:-}"
  PKG_NAME="${PKG_NAME:-TMRW-${VERSION}-TestFlight.pkg}"

  [ -n "$APP_PATH" ] || fail "APP_PATH is required"
  [ -n "$OUT_DIR" ] || fail "OUT_DIR is required"
  [ -n "${APP_SIGN_IDENTITY:-}" ] || fail "APP_SIGN_IDENTITY is required"
  [ -n "${INSTALLER_SIGN_IDENTITY:-}" ] || fail "INSTALLER_SIGN_IDENTITY is required"
  [ -n "${MAIN_PROVISION_PROFILE:-}" ] || fail "MAIN_PROVISION_PROFILE is required"
  [ -n "${PLUGIN_CONTAINER_PROVISION_PROFILE:-}" ] || fail "PLUGIN_CONTAINER_PROVISION_PROFILE is required"
  [ -d "$APP_PATH" ] || fail "APP_PATH does not exist: $APP_PATH"

  local app_plist="$APP_PATH/Contents/Info.plist"
  local plugin_app="$APP_PATH/Contents/MacOS/plugin-container.app"
  local plugin_plist="$plugin_app/Contents/Info.plist"
  [ -f "$app_plist" ] || fail "Missing main Info.plist: $app_plist"
  [ -d "$plugin_app" ] || fail "Missing plugin-container.app: $plugin_app"
  [ -f "$plugin_plist" ] || fail "Missing plugin-container Info.plist: $plugin_plist"

  mkdir -p "$OUT_DIR"

  note "Setting visible version to $VERSION"
  plist_set "$app_plist" CFBundleShortVersionString "$VERSION"
  plist_set "$app_plist" CFBundleVersion "$VERSION"
  plist_set "$app_plist" CFBundleGetInfoString "$VERSION"

  if [ -n "$PLUGIN_BUNDLE_ID" ]; then
    note "Setting plugin-container bundle id to $PLUGIN_BUNDLE_ID"
    plist_set "$plugin_plist" CFBundleIdentifier "$PLUGIN_BUNDLE_ID"
  fi

  note "Main bundle id: $(plist_get "$app_plist" CFBundleIdentifier)"
  note "Plugin bundle id: $(plist_get "$plugin_plist" CFBundleIdentifier)"

  note "Embedding provisioning profiles"
  copy_profile "$MAIN_PROVISION_PROFILE" "$APP_PATH"
  copy_profile "$PLUGIN_CONTAINER_PROVISION_PROFILE" "$plugin_app"

  note "Signing nested plugin-container.app first"
  sign_bundle "$plugin_app" "$PLUGIN_ENTITLEMENTS"

  note "Signing main TMRW.app"
  sign_bundle "$APP_PATH" "$MAIN_ENTITLEMENTS"

  note "Verifying signed bundles"
  verify_bundle_profile "$plugin_app" "plugin-container.app"
  verify_bundle_profile "$APP_PATH" "TMRW.app"

  local pkg_path="$OUT_DIR/$PKG_NAME"
  rm -f "$pkg_path"

  note "Building pkg: $pkg_path"
  productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$pkg_path"

  note "Verifying pkg signature"
  pkgutil --check-signature "$pkg_path"
  xcrun stapler validate "$pkg_path" >/dev/null 2>&1 || true

  note "Done: $pkg_path"
}

main "$@"
