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
#   APPLE_SIGNING_IDENTITY="Apple Distribution: Plato Technologies inc. (TEAMID)"
#   APPLE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Plato Technologies inc. (TEAMID)"
#   APPLE_PROVISIONING_PROFILE=/path/to/TMRW-main.provisionprofile
#   BUILT_APP_PATH=/path/to/TMRW.app
#
# Nested plugin-container .env variables:
#   APPLE_PLUGIN_CONTAINER_BUNDLE_ID=com.tmrw.w3ai.plugin-container
#   APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE=/path/to/TMRW-plugin-container.provisionprofile
#
# Optional .env variables:
#   TESTFLIGHT_OUT_DIR=obj-x86_64-apple-darwin25.5.0/dist   # defaults to dir containing BUILT_APP_PATH
#   TESTFLIGHT_PKG_NAME=TMRW-v1.2.1.pkg                    # defaults to TMRW-v{APP_VERSION}.pkg
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
  # Strip quarantine — cp inherits xattrs from downloaded source files (error 91109)
  xattr -d com.apple.quarantine "$bundle/Contents/embedded.provisionprofile" 2>/dev/null || true
}

# Merge arm64 slice from Mozilla's cached Universal DMG into every x86_64 Mach-O (fixes 91167).
# Uses obj-arm64-cache/firefox-nightly-mac-universal.dmg which notarize.sh downloads.
# Idempotent: already-fat binaries are skipped.
make_universal() {
  local app_path="$1"
  local root="$2"
  local dmg_cache="$root/obj-arm64-cache/firefox-nightly-mac-universal.dmg"
  local dmg_url="https://archive.mozilla.org/pub/firefox/nightly/latest-mozilla-central/firefox-154.0a1.en-US.mac.dmg"

  if [ ! -f "$dmg_cache" ]; then
    note "Downloading Firefox Universal DMG for arm64 slice (~172 MB)..."
    mkdir -p "$(dirname "$dmg_cache")"
    curl -L -o "$dmg_cache" "$dmg_url" --progress-bar 2>/dev/null || { note "  Download failed — skipping arm64 merge"; return 0; }
  fi

  local mnt="/tmp/tmrw-arm64-mnt"
  hdiutil detach "$mnt" -force -quiet 2>/dev/null || true
  hdiutil attach "$dmg_cache" -nobrowse -mountpoint "$mnt" -quiet || { note "  Could not mount DMG — skipping arm64 merge"; return 0; }

  local arm_src
  arm_src=$(find "$mnt" -maxdepth 1 -name "*.app" -type d | head -1)
  if [ -z "$arm_src" ]; then
    hdiutil detach "$mnt" -quiet 2>/dev/null || true
    note "  No .app in DMG — skipping arm64 merge"
    return 0
  fi

  note "Merging arm64 slices into bundle (fixes 91167)..."
  local _lipoed=0

  # Phase A: path-matched files
  while IFS= read -r -d '' x86f; do
    file "$x86f" 2>/dev/null | grep -q "Mach-O" || continue
    lipo -info "$x86f" 2>/dev/null | grep -q "arm64" && continue
    local rel="${x86f#$app_path/}"
    local armf="$arm_src/$rel"
    [ -f "$armf" ] || continue
    file "$armf" 2>/dev/null | grep -q "Mach-O" || continue
    local tmp
    tmp=$(mktemp /tmp/arm64-slice.XXXXXX)
    if lipo -extract arm64 "$armf" -output "$tmp" 2>/dev/null; then
      if lipo -create "$x86f" "$tmp" -output "$x86f.fat" 2>/dev/null; then
        mv "$x86f.fat" "$x86f"
        _lipoed=$((_lipoed + 1))
      fi
    fi
    rm -f "$tmp"
  done < <(find "$app_path" -type f -print0)

  # Phase B: nested .app helpers whose executable name may differ between versions
  while IFS= read -r nested; do
    [ "$nested" = "$app_path" ] && continue
    local dir
    dir=$(basename "$nested")
    local arm_nested="$arm_src/Contents/MacOS/$dir"
    [ -d "$arm_nested" ] || continue
    local our_exe arm_exe
    our_exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$nested/Contents/Info.plist" 2>/dev/null) || continue
    arm_exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$arm_nested/Contents/Info.plist" 2>/dev/null) || continue
    local our_bin="$nested/Contents/MacOS/$our_exe"
    local arm_bin="$arm_nested/Contents/MacOS/$arm_exe"
    [ -f "$our_bin" ] && [ -f "$arm_bin" ] || continue
    lipo -info "$our_bin" 2>/dev/null | grep -q "arm64" && continue
    local tmp
    tmp=$(mktemp /tmp/arm64-slice.XXXXXX)
    if lipo -extract arm64 "$arm_bin" -output "$tmp" 2>/dev/null; then
      if lipo -create "$our_bin" "$tmp" -output "$our_bin.fat" 2>/dev/null; then
        mv "$our_bin.fat" "$our_bin"
        _lipoed=$((_lipoed + 1))
      fi
    fi
    rm -f "$tmp"
  done < <(find "$app_path/Contents" -name "*.app" -type d | sort)

  hdiutil detach "$mnt" -quiet 2>/dev/null || true
  note "  Universal: $_lipoed binaries now contain x86_64 + arm64"
}

# Convert a flat framework (binary+Resources at root) to the required versioned layout:
#   Versions/A/{binary,Resources}   with symlinks at the root
# Idempotent: skipped if Versions/ already exists.
restructure_framework() {
  local fw_dir="$1"
  local fw_name="$2"
  [ -d "$fw_dir/Versions" ] && return 0
  note "  Restructuring flat framework: $fw_name"
  mkdir -p "$fw_dir/Versions/A"
  [ -f "$fw_dir/$fw_name" ] && [ ! -L "$fw_dir/$fw_name" ] && \
    mv "$fw_dir/$fw_name" "$fw_dir/Versions/A/$fw_name"
  [ -d "$fw_dir/Resources" ] && [ ! -L "$fw_dir/Resources" ] && \
    mv "$fw_dir/Resources" "$fw_dir/Versions/A/Resources"
  rm -rf "$fw_dir/_CodeSignature"
  ln -sf "A"                          "$fw_dir/Versions/Current"
  ln -sf "Versions/Current/$fw_name"  "$fw_dir/$fw_name"
  ln -sf "Versions/Current/Resources" "$fw_dir/Resources"
}

# Build a temp entitlements plist with application-identifier + team-identifier
# appended to the base file. Caller is responsible for deleting the temp file.
make_entitlements_with_appid() {
  local base="$1"      # source .entitlements file
  local app_id="$2"   # e.g. K9B6ZLA9M4.com.tmrw.w3ai
  local team_id="$3"  # e.g. K9B6ZLA9M4
  local tmp
  tmp="$(mktemp /tmp/entitlements.XXXXXX)"
  cp "$base" "$tmp"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $app_id" "$tmp" 2>/dev/null || \
  /usr/libexec/PlistBuddy \
    -c "Set :com.apple.application-identifier $app_id" "$tmp" 2>/dev/null || true
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.developer.team-identifier string $team_id" "$tmp" 2>/dev/null || \
  /usr/libexec/PlistBuddy \
    -c "Set :com.apple.developer.team-identifier $team_id" "$tmp" 2>/dev/null || true
  printf '%s\n' "$tmp"
}

sign_file() {
  local f="$1"
  codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" "$f" 2>/dev/null || true
}

sign_bundle() {
  local bundle="$1"
  local entitlements="$2"
  [ -d "$bundle" ] || fail "Bundle not found: $bundle"
  [ -f "$entitlements" ] || fail "Entitlements not found: $entitlements"
  codesign --force --options runtime --timestamp \
    --entitlements "$entitlements" \
    --sign "$APPLE_SIGNING_IDENTITY" "$bundle"
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
  TESTFLIGHT_OUT_DIR="${TESTFLIGHT_OUT_DIR:-$(dirname "${BUILT_APP_PATH:-obj-x86_64-apple-darwin25.5.0/dist/TMRW.app}")}"
  TESTFLIGHT_PKG_NAME="${TESTFLIGHT_PKG_NAME:-TMRW-v${APP_VERSION}.pkg}"
  MAIN_ENTITLEMENTS="${MAIN_ENTITLEMENTS:-build/macos/testflight/TMRW.entitlements}"
  PLUGIN_ENTITLEMENTS="${PLUGIN_ENTITLEMENTS:-build/macos/testflight/plugin-container.entitlements}"
  CRASHREPORTER_ENTITLEMENTS="${CRASHREPORTER_ENTITLEMENTS:-build/macos/testflight/crashreporter.entitlements}"

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

  [ -n "${BUILT_APP_PATH:-}" ]   || fail "BUILT_APP_PATH is required in .env"
  [ -n "${APPLE_SIGNING_IDENTITY:-}" ] || fail "APPLE_SIGNING_IDENTITY is required in .env"
  [ -n "${APPLE_INSTALLER_IDENTITY:-}" ] || fail "APPLE_INSTALLER_IDENTITY is required in .env"
  [ -n "${APPLE_PROVISIONING_PROFILE:-}" ] || fail "APPLE_PROVISIONING_PROFILE is required in .env"
  [ -n "${APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE:-}" ] || fail "APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE is required in .env"
  [ -n "${APPLE_TEAM_ID:-}" ] || fail "APPLE_TEAM_ID is required in .env"
  [ -n "${APPLE_BUNDLE_ID:-}" ] || fail "APPLE_BUNDLE_ID is required in .env"
  [ -n "${APPLE_PLUGIN_CONTAINER_BUNDLE_ID:-}" ] || fail "APPLE_PLUGIN_CONTAINER_BUNDLE_ID is required in .env"

  local app_path out_dir main_entitlements plugin_entitlements crashreporter_entitlements main_profile plugin_profile crashreporter_profile
  app_path="$(abs_path "$BUILT_APP_PATH" "$root")"
  out_dir="$(abs_path "$TESTFLIGHT_OUT_DIR" "$root")"
  main_entitlements="$(abs_path "$MAIN_ENTITLEMENTS" "$root")"
  plugin_entitlements="$(abs_path "$PLUGIN_ENTITLEMENTS" "$root")"
  crashreporter_entitlements="$(abs_path "$CRASHREPORTER_ENTITLEMENTS" "$root")"
  main_profile="$(abs_path "$APPLE_PROVISIONING_PROFILE" "$root")"
  plugin_profile="$(abs_path "$APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE" "$root")"
  crashreporter_profile="${APPLE_CRASHREPORTER_PROVISIONING_PROFILE:-}"
  [ -n "$crashreporter_profile" ] && crashreporter_profile="$(abs_path "$crashreporter_profile" "$root")"

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

  # Bypass App Store Connect export compliance dialog — standard TLS algorithms only
  /usr/libexec/PlistBuddy -c "Delete :ITSAppUsesNonExemptEncryption" "$app_plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$app_plist"

  note "Setting main bundle id to $APPLE_BUNDLE_ID"
  plist_set "$app_plist" CFBundleIdentifier "$APPLE_BUNDLE_ID"

  note "Setting plugin-container bundle id to $APPLE_PLUGIN_CONTAINER_BUNDLE_ID"
  plist_set "$plugin_plist" CFBundleIdentifier "$APPLE_PLUGIN_CONTAINER_BUNDLE_ID"

  note "Main bundle id: $(plist_get "$app_plist" CFBundleIdentifier)"
  note "Plugin bundle id: $(plist_get "$plugin_plist" CFBundleIdentifier)"

  note "Embedding provisioning profiles"
  copy_profile "$main_profile" "$app_path"
  copy_profile "$plugin_profile" "$plugin_app"
  local cr_app="$app_path/Contents/MacOS/crashreporter.app"
  if [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ]; then
    copy_profile "$crashreporter_profile" "$cr_app"
    note "  Embedded crashreporter provisioning profile"
  fi

  # Build temp entitlements with application-identifier injected
  local main_app_id="${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}"
  local plugin_app_id="${APPLE_TEAM_ID}.${APPLE_PLUGIN_CONTAINER_BUNDLE_ID}"
  local crashreporter_bundle_id="com.tmrw.w3ai.crashreporter"
  local crashreporter_app_id="${APPLE_TEAM_ID}.${crashreporter_bundle_id}"
  local tmp_main_ent tmp_plugin_ent tmp_helper_ent tmp_cr_ent
  tmp_main_ent=""
  tmp_plugin_ent=""
  tmp_helper_ent=""
  tmp_cr_ent=""
  trap 'rm -f "${tmp_main_ent:-}" "${tmp_plugin_ent:-}" "${tmp_helper_ent:-}" "${tmp_cr_ent:-}"' EXIT
  tmp_main_ent="$(make_entitlements_with_appid "$main_entitlements" "$main_app_id" "$APPLE_TEAM_ID")"
  tmp_plugin_ent="$(make_entitlements_with_appid "$plugin_entitlements" "$plugin_app_id" "$APPLE_TEAM_ID")"
  tmp_cr_ent="$(make_entitlements_with_appid "$crashreporter_entitlements" "$crashreporter_app_id" "$APPLE_TEAM_ID")"

  # Helper entitlements for all other nested .app bundles (sandbox + JIT flags only)
  tmp_helper_ent="$(mktemp /tmp/entitlements-helper.XXXXXX)"
  cat > "$tmp_helper_ent" <<'ENTXML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENTXML

  # Step 0: Remove build artifacts and non-distribution binaries that either
  # cause "code object not signed" failures or 409 App Sandbox rejections.
  note "Removing build artifacts and non-distribution binaries..."
  # Build system markers
  find "$app_path/Contents" -name "moz.build" -delete 2>/dev/null || true
  find "$app_path/Contents" -name "*.mk"      -delete 2>/dev/null || true
  find "$app_path/Contents" -name "Makefile"  -delete 2>/dev/null || true
  find "$app_path/Contents" -name "*.done"    -delete 2>/dev/null || true
  # Test-only dylibs (gtest build-id stubs) — not permitted and cannot be signed
  rm -rf "${app_path:?}/Contents/MacOS/gtest" 2>/dev/null || true

  # Development/debug binaries not permitted in App Store builds (cause 409)
  for _dev_bin in signmar logalloc-replay zucchini zucchini-gtest; do
    rm -f "${app_path:?}/Contents/Resources/$_dev_bin" 2>/dev/null || true
    rm -f "${app_path:?}/Contents/MacOS/$_dev_bin"     2>/dev/null || true
  done
  # Binary-patch backup file
  rm -f "${app_path:?}/Contents/Resources/firefox.bak" \
        "${app_path:?}/Contents/MacOS/firefox.bak" 2>/dev/null || true
  # Stale Mozilla updater manifest in Resources/ duplicates updater.app/Contents/Info.plist
  # with the same CFBundleExecutable=org.mozilla.updater → Transporter 409 conflict.
  rm -f "${app_path:?}/Contents/Resources/Info.plist" 2>/dev/null || true

  # dependentlibs.list is required by XPCOMGlueLoad on macOS to find XUL.
  # The artifact build omits it from TMRW.app; copy from the build output bin/.
  local _deplibs_dst="$app_path/Contents/Resources/dependentlibs.list"
  if [ ! -f "$_deplibs_dst" ]; then
    local _deplibs_src
    _deplibs_src="$(find "$root/obj-x86_64-apple-darwin25.5.0/toolkit/library/build" \
                         "$root/obj-x86_64-apple-darwin25.5.0/dist/bin" \
                         -name "dependentlibs.list" -not -type l 2>/dev/null | head -1)"
    if [ -n "$_deplibs_src" ]; then
      cp "$_deplibs_src" "$_deplibs_dst"
      note "Copied dependentlibs.list → Contents/Resources/"
    else
      note "WARNING: dependentlibs.list not found; XPCOMGlue will fail to launch"
    fi
  fi

  # Patch crashreporter.app — artifact download retains Mozilla "Nightly Crash Reporter" branding
  local _cr_app="$app_path/Contents/MacOS/crashreporter.app"
  local _cr_plist="$_cr_app/Contents/Info.plist"
  local _cr_strings="$_cr_app/Contents/Resources/English.lproj/InfoPlist.strings"
  if [ -f "$_cr_plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Crash Reporter" "$_cr_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW Crash Reporter" "$_cr_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Crash Reporter" "$_cr_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string TMRW Crash Reporter" "$_cr_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.tmrw.w3ai.crashreporter" "$_cr_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :LSHasLocalizedDisplayName false" "$_cr_plist" 2>/dev/null || true
    note "Patched crashreporter.app display name → TMRW Crash Reporter"
  fi
  if [ -f "$_cr_strings" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Crash Reporter" "$_cr_strings" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Crash Reporter" "$_cr_strings" 2>/dev/null || true
  fi

  # Resolve nmhproxy symlink to a real file so it can be signed
  _NMH_LINK="$app_path/Contents/MacOS/nmhproxy"
  if [ -L "$_NMH_LINK" ]; then
    _NMH_TARGET="$(readlink "$_NMH_LINK")"
    if [ -f "$_NMH_TARGET" ]; then
      cp -f "$_NMH_TARGET" "${_NMH_LINK}.real"
      rm -f "$_NMH_LINK"
      mv "${_NMH_LINK}.real" "$_NMH_LINK"
      note "  Resolved nmhproxy symlink to real binary"
    fi
  fi

  # Remove all symlinks whose targets are outside the bundle (test binaries, dev stubs).
  # Legitimate framework versioning symlinks (Versions/Current -> A) stay because
  # their targets resolve inside the bundle.
  _removed_links=0
  while IFS= read -r lnk; do
    _tgt="$(readlink "$lnk")"
    case "$_tgt" in
      /*) rm -f "$lnk"; _removed_links=$((_removed_links+1)) ;;
    esac
  done < <(find "$app_path" -type l 2>/dev/null)
  note "  Removed $_removed_links external symlinks (test binaries)"

  # Merge arm64 slice into all x86_64 binaries → Universal Binary (fixes 91167)
  make_universal "$app_path" "$root"

  # Restructure flat frameworks to proper versioned layout (Transporter 90291/90292)
  note "Restructuring frameworks to versioned layout..."
  restructure_framework \
    "$app_path/Contents/Frameworks/ChannelPrefs.framework" \
    "ChannelPrefs"
  restructure_framework \
    "$app_path/Contents/MacOS/updater.app/Contents/Frameworks/UpdateSettings.framework" \
    "UpdateSettings"

  # Step 1: Sign ALL Mach-O files in Resources/ and Library/ with sandbox entitlements.
  # This covers dylibs, .so, and standalone executables (firefox-bin, pingsender,
  # plugin-container flat binary, org.mozilla.updater, etc.) — the full set that
  # Transporter validates for "com.apple.security.app-sandbox" (error 409).
  note "Signing Mach-O files in Resources/ and Library/..."
  local _signed=0
  while IFS= read -r -d '' f; do
    file "$f" 2>/dev/null | grep -q "Mach-O" || continue
    codesign --force --timestamp --options runtime \
      --entitlements "$tmp_helper_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$f" 2>/dev/null || true
    _signed=$((_signed + 1))
  done < <(find \
    "$app_path/Contents/Resources" \
    "$app_path/Contents/Library" \
    -type f -print0 2>/dev/null)
  note "  Signed $_signed Mach-O files"

  # Step 2: Sign loose Mach-O executables in MacOS/ (XUL, crashhelper, pingsender…)
  note "Signing executables in MacOS/..."
  _signed=0
  while IFS= read -r -d '' f; do
    file "$f" 2>/dev/null | grep -q "Mach-O" || continue
    codesign --force --timestamp --options runtime \
      --entitlements "$tmp_helper_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$f" 2>/dev/null || true
    _signed=$((_signed + 1))
  done < <(find "$app_path/Contents/MacOS" -maxdepth 1 \
    -not -name "*.app" \
    -type f -print0 2>/dev/null)
  note "  Signed $_signed executables"

  # Step 2b: Sign frameworks with sandbox entitlements
  note "Signing frameworks..."
  while IFS= read -r fw; do
    note "  $(basename "$fw")"
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_helper_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$fw"
  done < <(find "$app_path/Contents/Frameworks" -name "*.framework" -type d -maxdepth 1 2>/dev/null)

  # Step 3: Sign nested .app bundles — plugin-container last among peers so its
  # provisioning profile is in place before the main bundle seals it.
  note "Signing nested helper apps..."
  local _cr_has_profile=false
  [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ] && _cr_has_profile=true

  while IFS= read -r nested; do
    [[ "$nested" == "$app_path" ]] && continue
    [[ "$nested" == "$plugin_app" ]] && continue  # handled separately below
    [[ "$nested" == "$cr_app" ]]    && continue  # handled separately below
    local nested_name
    nested_name="$(basename "$nested")"
    note "  $nested_name"
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_helper_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$nested"
  done < <(find "$app_path/Contents" -name "*.app" -type d | sort -r)

  note "Signing crashreporter.app"
  if [ "$_cr_has_profile" = true ]; then
    sign_bundle "$cr_app" "$tmp_cr_ent"
  else
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_cr_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$cr_app"
  fi

  note "Signing plugin-container.app"
  sign_bundle "$plugin_app" "$tmp_plugin_ent"

  # Step 4: Seal the main bundle (no --deep; inner code already signed above)
  note "Signing main TMRW.app"
  sign_bundle "$app_path" "$tmp_main_ent"

  note "Verifying signed bundles"
  [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ] && \
    verify_bundle_profile "$cr_app" "crashreporter.app"
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
