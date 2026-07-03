#!/usr/bin/env bash
set -euo pipefail

# Package TMRW.app for Mac TestFlight/App Store Connect.
#
# This script reads signing/package settings from .env by default so Apple
# secrets and local signing paths stay in one place. Environment variables
# passed directly to this command still override .env values.
#
# Main .env variables:
#   APP_VERSION=1.2.1
#   APPLE_ID=developer@example.com
#   APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
#   APPLE_TEAM_ID=TEAMID1234
#   APPLE_BUNDLE_ID=com.tmrw.w3ai
#   APPLE_SIGNING_IDENTITY="3rd Party Mac Developer Application: Plato Technologies inc. (TEAMID)"
#   APPLE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Plato Technologies inc. (TEAMID)"
#   APPLE_PROVISIONING_PROFILE=/path/to/TMRW-main.provisionprofile
#   BUILT_APP_PATH=/path/to/TMRW.app
#
# Nested plugin-container .env variables:
#   APPLE_PLUGIN_CONTAINER_BUNDLE_ID=com.tmrw.w3ai.plugin-container
#   APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE=/path/to/TMRW-plugin-container.provisionprofile
#
# Optional .env variables:
#   TESTFLIGHT_OUT_DIR=dist-testflight
#   TESTFLIGHT_PKG_NAME=TMRW-1.2.1-TestFlight.pkg
#   MAIN_ENTITLEMENTS=build/macos/testflight/TMRW.entitlements
#   PLUGIN_ENTITLEMENTS=build/macos/testflight/plugin-container.entitlements

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

load_env_file() {
  local env_file="${ENV_FILE:-.env}"
  if [ -f "$env_file" ]; then
    note "Loading settings from $env_file"
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  else
    note "No $env_file file found; using exported environment only"
  fi
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

abs_path() {
  local value="$1"
  local root="$2"
  [ -n "$value" ] || return 0
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    ~/*) printf '%s\n' "${HOME}${value#~}" ;;
    *) printf '%s\n' "$root/$value" ;;
  esac
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
  codesign --force --options runtime --timestamp --entitlements "$entitlements" --sign "$APPLE_SIGNING_IDENTITY" "$bundle"
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

  local root
  root="$(repo_root)"
  cd "$root"
  load_env_file

  APP_VERSION="${APP_VERSION:-1.2.1}"
  BUILT_APP_PATH="${BUILT_APP_PATH:-}"
  TESTFLIGHT_OUT_DIR="${TESTFLIGHT_OUT_DIR:-dist-testflight}"
  TESTFLIGHT_PKG_NAME="${TESTFLIGHT_PKG_NAME:-TMRW-${APP_VERSION}-TestFlight.pkg}"
  MAIN_ENTITLEMENTS="${MAIN_ENTITLEMENTS:-build/macos/testflight/TMRW.entitlements}"
  PLUGIN_ENTITLEMENTS="${PLUGIN_ENTITLEMENTS:-build/macos/testflight/plugin-container.entitlements}"

  # Backward compatible overrides for earlier command examples.
  if [ -n "${VERSION:-}" ]; then APP_VERSION="$VERSION"; fi
  if [ -n "${APP_PATH:-}" ]; then BUILT_APP_PATH="$APP_PATH"; fi
  if [ -n "${OUT_DIR:-}" ]; then TESTFLIGHT_OUT_DIR="$OUT_DIR"; fi
  if [ -n "${PKG_NAME:-}" ]; then TESTFLIGHT_PKG_NAME="$PKG_NAME"; fi
  if [ -n "${APP_SIGN_IDENTITY:-}" ]; then APPLE_SIGNING_IDENTITY="$APP_SIGN_IDENTITY"; fi
  if [ -n "${INSTALLER_SIGN_IDENTITY:-}" ]; then APPLE_INSTALLER_IDENTITY="$INSTALLER_SIGN_IDENTITY"; fi
  if [ -n "${MAIN_PROVISION_PROFILE:-}" ]; then APPLE_PROVISIONING_PROFILE="$MAIN_PROVISION_PROFILE"; fi
  if [ -n "${PLUGIN_CONTAINER_PROVISION_PROFILE:-}" ]; then APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE="$PLUGIN_CONTAINER_PROVISION_PROFILE"; fi
  if [ -n "${PLUGIN_BUNDLE_ID:-}" ]; then APPLE_PLUGIN_CONTAINER_BUNDLE_ID="$PLUGIN_BUNDLE_ID"; fi

  [ -n "${BUILT_APP_PATH:-}" ] || fail "BUILT_APP_PATH is required in .env"
  [ -n "${APPLE_SIGNING_IDENTITY:-}" ] || fail "APPLE_SIGNING_IDENTITY is required in .env"
  [ -n "${APPLE_INSTALLER_IDENTITY:-}" ] || fail "APPLE_INSTALLER_IDENTITY is required in .env"
  [ -n "${APPLE_PROVISIONING_PROFILE:-}" ] || fail "APPLE_PROVISIONING_PROFILE is required in .env"
  [ -n "${APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE:-}" ] || fail "APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE is required in .env"

  local app_path out_dir main_entitlements plugin_entitlements main_profile plugin_profile
  app_path="$(abs_path "$BUILT_APP_PATH" "$root")"
  out_dir="$(abs_path "$TESTFLIGHT_OUT_DIR" "$root")"
  main_entitlements="$(abs_path "$MAIN_ENTITLEMENTS" "$root")"
  plugin_entitlements="$(abs_path "$PLUGIN_ENTITLEMENTS" "$root")"
  main_profile="$(abs_path "$APPLE_PROVISIONING_PROFILE" "$root")"
  plugin_profile="$(abs_path "$APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE" "$root")"

  [ -d "$app_path" ] || fail "BUILT_APP_PATH does not exist: $app_path"

  local app_plist="$app_path/Contents/Info.plist"
  local plugin_app="$app_path/Contents/MacOS/plugin-container.app"
  local plugin_plist="$plugin_app/Contents/Info.plist"
  [ -f "$app_plist" ] || fail "Missing main Info.plist: $app_plist"
  [ -d "$plugin_app" ] || fail "Missing plugin-container.app: $plugin_app"
  [ -f "$plugin_plist" ] || fail "Missing plugin-container Info.plist: $plugin_plist"

  mkdir -p "$out_dir"

  note "Setting visible version to $APP_VERSION"
  plist_set "$app_plist" CFBundleShortVersionString "$APP_VERSION"
  plist_set "$app_plist" CFBundleVersion "$APP_VERSION"
  plist_set "$app_plist" CFBundleGetInfoString "$APP_VERSION"

  if [ -n "${APPLE_BUNDLE_ID:-}" ]; then
    note "Setting main bundle id to $APPLE_BUNDLE_ID"
    plist_set "$app_plist" CFBundleIdentifier "$APPLE_BUNDLE_ID"
  fi

  if [ -n "${APPLE_PLUGIN_CONTAINER_BUNDLE_ID:-}" ]; then
    note "Setting plugin-container bundle id to $APPLE_PLUGIN_CONTAINER_BUNDLE_ID"
    plist_set "$plugin_plist" CFBundleIdentifier "$APPLE_PLUGIN_CONTAINER_BUNDLE_ID"
  fi

  note "Main bundle id: $(plist_get "$app_plist" CFBundleIdentifier)"
  note "Plugin bundle id: $(plist_get "$plugin_plist" CFBundleIdentifier)"

  note "Embedding provisioning profiles"
  copy_profile "$main_profile" "$app_path"
  copy_profile "$plugin_profile" "$plugin_app"

  note "Signing nested plugin-container.app first"
  sign_bundle "$plugin_app" "$plugin_entitlements"

  note "Signing main TMRW.app"
  sign_bundle "$app_path" "$main_entitlements"

  note "Verifying signed bundles"
  verify_bundle_profile "$plugin_app" "plugin-container.app"
  verify_bundle_profile "$app_path" "TMRW.app"

  local pkg_path="$out_dir/$TESTFLIGHT_PKG_NAME"
  rm -f "$pkg_path"

  note "Building pkg: $pkg_path"
  productbuild --component "$app_path" /Applications --sign "$APPLE_INSTALLER_IDENTITY" "$pkg_path"

  note "Verifying pkg signature"
  pkgutil --check-signature "$pkg_path"
  xcrun stapler validate "$pkg_path" >/dev/null 2>&1 || true

  note "Done: $pkg_path"
}

main "$@"
