#!/usr/bin/env bash
set -euo pipefail

# Package TMRW.app for Mac TestFlight/App Store Connect.
#
# This script reads signing/package settings from .env by default so Apple
# secrets and local signing paths stay in one place. Environment variables
# passed directly to this command still override .env values.
#
# Main .env variables:
#   APP_VERSION=1.2.9                                       # required — no hardcoded fallback
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
# Nested updater .env variables:
#   APPLE_UPDATER_BUNDLE_ID=com.tmrw.w3ai.updater            # optional, defaults to com.tmrw.w3ai.updater
#   APPLE_UPDATER_PROVISIONING_PROFILE=/path/to/TMRW-Updater.provisionprofile
#
# Optional .env variables:
#   TESTFLIGHT_OUT_DIR=obj-x86_64-apple-darwin25.5.0/dist   # defaults to dir containing BUILT_APP_PATH
#   TESTFLIGHT_PKG_NAME=TMRW-v{APP_VERSION}.pkg              # defaults to TMRW-v{APP_VERSION}.pkg
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

# Transporter error 409 "Invalid Code Signature Identifier" happens when the code
# signature's Identifier (baked in at sign time from Info.plist) no longer matches
# the CFBundleIdentifier actually on disk in the shipped bundle. Catch that locally
# instead of finding out after an upload.
verify_identifier_match() {
  local bundle="$1"
  local label="$2"
  local plist_id sig_id
  plist_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle/Contents/Info.plist" 2>/dev/null)"
  sig_id="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^Identifier=//p')"
  if [ "$plist_id" != "$sig_id" ]; then
    fail "$label: code signature identifier ('$sig_id') does not match CFBundleIdentifier ('$plist_id') — re-sign after patching Info.plist"
  fi
  note "  $label identifier OK: $plist_id"
}

# Transporter error 90885 ("missing a provisioning profile but has an
# application identifier in its signature") happens when ANY signed Mach-O
# file — bundle or loose executable — carries an application-identifier
# entitlement without a provisioning profile to back it. A loose (non-bundle)
# executable can never have one, so it must never carry this entitlement at
# all; a bundle must have Contents/embedded.provisionprofile if it does.
# Scans the whole app after signing so this can't silently regress again.
verify_no_orphan_appid() {
  local app_path="$1"
  local f is_bundle bundle_root ent
  while IFS= read -r -d '' f; do
    file "$f" 2>/dev/null | grep -q "Mach-O" || continue
    ent="$(codesign -d --entitlements - "$f" 2>&1)"
    echo "$ent" | grep -q "application-identifier" || continue
    is_bundle=false
    is_framework=false
    bundle_root=""
    case "$f" in
      */Contents/MacOS/*)
        bundle_root="${f%/Contents/MacOS/*}"
        [ -d "$bundle_root" ] && [ "$(basename "$bundle_root")" != "MacOS" ] && \
          case "$bundle_root" in *.app|*.framework) is_bundle=true ;; esac
        ;;
      */Versions/*/*)
        # Framework binaries live at Foo.framework/Versions/A/Foo, not under a
        # Contents/MacOS tree — this class of path was previously invisible to
        # this check entirely, letting an orphaned application-identifier
        # entitlement on a framework binary slip past silently.
        bundle_root="${f%/Versions/*}"
        [ -d "$bundle_root" ] && case "$bundle_root" in *.framework) is_bundle=true; is_framework=true ;; esac
        ;;
    esac
    if [ "$is_framework" = true ]; then
      fail "$f (inside a .framework) has an application-identifier entitlement — frameworks can never carry a provisioning profile, this must be signed without application-identifier (Transporter 90885)"
    elif [ "$is_bundle" = true ]; then
      [ -f "$bundle_root/Contents/embedded.provisionprofile" ] || \
        fail "$f has an application-identifier entitlement but $bundle_root is missing Contents/embedded.provisionprofile (Transporter 90885)"
    else
      fail "$f is a loose executable with an application-identifier entitlement but no bundle to hold a provisioning profile (Transporter 90885) — it must be signed without application-identifier"
    fi
  done < <(find "$app_path/Contents" -type f -print0 2>/dev/null)
  note "  No orphaned application-identifier entitlements found"
}

# Catches the class of bug found 2026-07-04: a stale executable left in a
# nested .app's Contents/MacOS/ from an earlier build under different
# branding (e.g. an old thin-arch binary sitting next to the real,
# universal-arch one CFBundleExecutable actually points to). --deep signing
# resigns every Mach-O it finds there regardless of whether Info.plist
# declares it, so an orphan silently picks up the same identity/entitlements
# as the bundle's real executable — undetectable by entitlement-only checks
# since the orphan looks "correctly" signed on its own.
verify_no_undeclared_executable() {
  local app_path="$1"
  local nested plist exe f
  while IFS= read -r nested; do
    [ "$nested" = "$app_path" ] && continue
    plist="$nested/Contents/Info.plist"
    [ -f "$plist" ] || continue
    exe="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)" || continue
    [ -n "$exe" ] || continue
    while IFS= read -r -d '' f; do
      [ "$(basename "$f")" = "$exe" ] && continue
      file "$f" 2>/dev/null | grep -q "Mach-O" || continue
      fail "$f is an undeclared executable in $(basename "$nested") — Info.plist's CFBundleExecutable is '$exe', not '$(basename "$f")' (would be silently re-signed with the bundle's identity by --deep)"
    done < <(find "$nested/Contents/MacOS" -maxdepth 1 -type f -print0 2>/dev/null)
  done < <(find "$app_path/Contents/MacOS" -name "*.app" -type d)
  note "  No undeclared executables found in nested .app bundles"
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

  [ -n "${APP_VERSION:-}" ] || fail "APP_VERSION is required in .env (no hardcoded fallback)"
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

  # Updater bundle id defaults to com.tmrw.w3ai.updater if not set. The
  # provisioning profile is optional: if present, updater.app gets its own
  # dedicated identity (like plugin-container/crashreporter); if absent, it
  # falls back to sharing the main app's identity (see tmp_shared_id_ent below).
  APPLE_UPDATER_BUNDLE_ID="${APPLE_UPDATER_BUNDLE_ID:-com.tmrw.w3ai.updater}"

  local app_path out_dir main_entitlements plugin_entitlements crashreporter_entitlements main_profile plugin_profile crashreporter_profile updater_profile
  app_path="$(abs_path "$BUILT_APP_PATH" "$root")"
  out_dir="$(abs_path "$TESTFLIGHT_OUT_DIR" "$root")"
  main_entitlements="$(abs_path "$MAIN_ENTITLEMENTS" "$root")"
  plugin_entitlements="$(abs_path "$PLUGIN_ENTITLEMENTS" "$root")"
  crashreporter_entitlements="$(abs_path "$CRASHREPORTER_ENTITLEMENTS" "$root")"
  main_profile="$(abs_path "$APPLE_PROVISIONING_PROFILE" "$root")"
  plugin_profile="$(abs_path "$APPLE_PLUGIN_CONTAINER_PROVISIONING_PROFILE" "$root")"
  crashreporter_profile="${APPLE_CRASHREPORTER_PROVISIONING_PROFILE:-}"
  [ -n "$crashreporter_profile" ] && crashreporter_profile="$(abs_path "$crashreporter_profile" "$root")"
  updater_profile="${APPLE_UPDATER_PROVISIONING_PROFILE:-}"
  [ -n "$updater_profile" ] && updater_profile="$(abs_path "$updater_profile" "$root")"

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

  # Updater identity: dedicated (own App ID + provisioning profile) when
  # APPLE_UPDATER_PROVISIONING_PROFILE is set (it now is — TMRW-Updater.provisionprofile
  # covers K9B6ZLA9M4.com.tmrw.w3ai.updater), otherwise falls back to the
  # collision-safe distinct-identifier/shared-entitlements approach already in
  # place below (avoids error 90049/90885 if the profile is ever removed).
  local _upd_app="$app_path/Contents/MacOS/updater.app"
  local updater_has_profile=false
  [ -n "$updater_profile" ] && [ -f "$updater_profile" ] && updater_has_profile=true
  local updater_bundle_id="$APPLE_UPDATER_BUNDLE_ID"

  note "Embedding provisioning profiles"
  copy_profile "$main_profile" "$app_path"
  copy_profile "$plugin_profile" "$plugin_app"
  local cr_app="$app_path/Contents/MacOS/crashreporter.app"
  if [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ]; then
    copy_profile "$crashreporter_profile" "$cr_app"
    note "  Embedded crashreporter provisioning profile"
  fi
  if [ "$updater_has_profile" = true ]; then
    copy_profile "$updater_profile" "$_upd_app"
    note "  Embedded updater provisioning profile"
  fi

  # Build temp entitlements with application-identifier injected
  local main_app_id="${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}"
  local plugin_app_id="${APPLE_TEAM_ID}.${APPLE_PLUGIN_CONTAINER_BUNDLE_ID}"
  local crashreporter_bundle_id="com.tmrw.w3ai.crashreporter"
  local crashreporter_app_id="${APPLE_TEAM_ID}.${crashreporter_bundle_id}"
  local updater_app_id="${APPLE_TEAM_ID}.${updater_bundle_id}"
  local tmp_main_ent tmp_plugin_ent tmp_helper_ent tmp_cr_ent tmp_shared_id_ent tmp_upd_ent
  tmp_main_ent=""
  tmp_plugin_ent=""
  tmp_helper_ent=""
  tmp_cr_ent=""
  tmp_shared_id_ent=""
  tmp_upd_ent=""
  trap 'rm -f "${tmp_main_ent:-}" "${tmp_plugin_ent:-}" "${tmp_helper_ent:-}" "${tmp_cr_ent:-}" "${tmp_shared_id_ent:-}" "${tmp_upd_ent:-}"' EXIT
  tmp_main_ent="$(make_entitlements_with_appid "$main_entitlements" "$main_app_id" "$APPLE_TEAM_ID")"
  tmp_plugin_ent="$(make_entitlements_with_appid "$plugin_entitlements" "$plugin_app_id" "$APPLE_TEAM_ID")"
  tmp_cr_ent="$(make_entitlements_with_appid "$crashreporter_entitlements" "$crashreporter_app_id" "$APPLE_TEAM_ID")"

  # Generic entitlements for loose (non-bundle) Mach-O files and frameworks —
  # dylibs, standalone tools (ssltunnel, certutil, pingsender, crashhelper...),
  # and the loose TMRWUpdater copies. These can never have an embedded
  # provisioning profile of their own (they're not bundles), so they must NOT
  # carry an application-identifier entitlement — Transporter's TestFlight
  # check (error 90885) rejects any signed executable that has an
  # application-identifier but no matching provisioning profile alongside it.
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

  # Separate entitlements for .app bundles that share the main app's identity:
  # gpu-helper.app, media-plugin-helper.app, security-module-helper.app,
  # callback_app.app always; updater.app too, but only as a fallback when
  # APPLE_UPDATER_PROVISIONING_PROFILE isn't set (see tmp_upd_ent below for
  # its normal, dedicated-identity path). Unlike the loose files above, these
  # ARE bundles and each gets a copy of the main app's own
  # embedded.provisionprofile (see above), so an application-identifier here
  # is valid and required — App Sandbox needs a provisioned identity, and none
  # of these have their own Apple Developer App ID.
  tmp_shared_id_ent="$(mktemp /tmp/entitlements-shared-id.XXXXXX)"
  cat > "$tmp_shared_id_ent" <<ENTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>${main_app_id}</string>
  <key>com.apple.developer.team-identifier</key><string>${APPLE_TEAM_ID}</string>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENTXML

  # Dedicated entitlements for updater.app ONLY, used when
  # APPLE_UPDATER_PROVISIONING_PROFILE is actually set — its own App ID,
  # backed by its own embedded provisioning profile (see above). Must NOT be
  # used without a matching profile (that's exactly the shape of 90049/90885),
  # so signing falls back to tmp_shared_id_ent whenever updater_has_profile is
  # false.
  if [ "$updater_has_profile" = true ]; then
    tmp_upd_ent="$(mktemp /tmp/entitlements-updater.XXXXXX)"
    cat > "$tmp_upd_ent" <<ENTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>${updater_app_id}</string>
  <key>com.apple.developer.team-identifier</key><string>${APPLE_TEAM_ID}</string>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENTXML
  fi

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

  # Patch crashreporter.app — artifact retains Mozilla "Nightly Crash Reporter" branding
  local _cr_app="$app_path/Contents/MacOS/crashreporter.app"
  local _cr_plist="$_cr_app/Contents/Info.plist"
  local _cr_strings="$_cr_app/Contents/Resources/English.lproj/InfoPlist.strings"
  if [ -f "$_cr_plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Crash Reporter" "$_cr_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW Crash Reporter" "$_cr_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Crash Reporter" "$_cr_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string TMRW Crash Reporter" "$_cr_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.tmrw.w3ai.crashreporter" "$_cr_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.tmrw.w3ai.crashreporter" "$_cr_plist"
    /usr/libexec/PlistBuddy -c "Set :LSHasLocalizedDisplayName false" "$_cr_plist" 2>/dev/null || true
    note "Patched crashreporter.app display name → TMRW Crash Reporter"
  fi
  if [ -f "$_cr_strings" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Crash Reporter" "$_cr_strings" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Crash Reporter" "$_cr_strings" 2>/dev/null || true
  fi

  # Patch updater.app — artifact retains Mozilla "Nightly Software Update" branding.
  # CFBundleIdentifier is $updater_bundle_id (com.tmrw.w3ai.updater by default,
  # from APPLE_UPDATER_BUNDLE_ID) — distinct from the main app's own identifier
  # either way (Apple's App Store validator rejects a nested bundle sharing its
  # parent's exact identifier as a "CFBundleIdentifier Collision", reported
  # confusingly as "invalid CFBundleIdentifier ''", Transporter error 90049).
  # Whether that identifier is backed by its own dedicated provisioning profile
  # (entitlements) or falls back to sharing the main app's is decided above via
  # updater_has_profile / tmp_upd_ent vs tmp_shared_id_ent — this Info.plist
  # patch is the same regardless.
  local _upd_plist="$_upd_app/Contents/Info.plist"
  local _upd_strings
  _upd_strings="$(find "$_upd_app" -name "InfoPlist.strings" 2>/dev/null | head -1)"
  if [ -f "$_upd_plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Software Update" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW Software Update" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRWUpdater" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string TMRWUpdater" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${updater_bundle_id}" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${updater_bundle_id}" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${APP_VERSION}" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_VERSION}" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${APP_VERSION}" "$_upd_plist"
    /usr/libexec/PlistBuddy -c "Set :LSHasLocalizedDisplayName false" "$_upd_plist" 2>/dev/null || true
    note "Patched updater.app → CFBundleIdentifier=${updater_bundle_id}, CFBundleName=TMRWUpdater, version=${APP_VERSION}"
  fi
  if [ -n "$_upd_strings" ] && [ -f "$_upd_strings" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Software Update" "$_upd_strings" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Software Update" "$_upd_strings" 2>/dev/null || true
  fi

  # Rename the updater executable itself away from "org.mozilla.updater" — an
  # org.mozilla.* name left in a com.tmrw.w3ai-signed bundle is its own red flag
  # for App Store review, independent of the entitlement fix above. Avoid dots
  # in the replacement name too: Transporter's validator has been observed
  # treating a dotted filename directly under a Contents/MacOS/ tree as if it
  # were its own nested bundle (error 90049) — "TMRWUpdater" avoids that class
  # of problem as well as the branding issue.
  local _upd_old_bin="$_upd_app/Contents/MacOS/org.mozilla.updater"
  local _upd_new_bin="$_upd_app/Contents/MacOS/TMRWUpdater"
  if [ -f "$_upd_old_bin" ]; then
    mv "$_upd_old_bin" "$_upd_new_bin"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable TMRWUpdater" "$_upd_plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string TMRWUpdater" "$_upd_plist"
    note "Renamed updater executable → TMRWUpdater"
  fi

  # Same loose (non-bundle) copies Firefox drops alongside the app for
  # LaunchServices/relaunch bookkeeping. Inert for App Store builds (App Store
  # delivers updates; the in-app MAR updater never runs — see notarize.sh), but
  # still get code-signed as-is, so rename them too or the next Transporter
  # submission just reports the identical error against a different path.
  for _loose in \
    "$app_path/Contents/Resources/org.mozilla.updater" \
    "$app_path/Contents/Library/LaunchServices/org.mozilla.updater"; do
    [ -f "$_loose" ] && mv "$_loose" "$(dirname "$_loose")/TMRWUpdater"
  done

  # Re-brand remaining org.mozilla.* helper bundle IDs. Each gets its own
  # distinct CFBundleIdentifier — NOT the main app's exact identifier, which
  # Apple's App Store validator rejects as a "CFBundleIdentifier Collision"
  # (see the updater.app comment above; same fix, same reason). Their
  # *entitlements* application-identifier (tmp_shared_id_ent) still points at
  # the main app's shared identity/profile, since none of them have their own
  # Apple Developer App ID — that field is independent of CFBundleIdentifier.
  local _hplist _hbundle
  for _hpair in \
    "gpu-helper.app=${APPLE_BUNDLE_ID}.gpu-helper" \
    "media-plugin-helper.app=${APPLE_BUNDLE_ID}.media-plugin-helper" \
    "security-module-helper.app=${APPLE_BUNDLE_ID}.security-module-helper" \
    "callback_app.app=${APPLE_BUNDLE_ID}.callback-app"; do
    local _hname="${_hpair%%=*}"
    local _hid="${_hpair##*=}"
    _hplist="$app_path/Contents/MacOS/$_hname/Contents/Info.plist"
    if [ -f "$_hplist" ]; then
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $_hid" "$_hplist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $_hid" "$_hplist"
      note "Patched $_hname bundle ID → $_hid"
    fi
  done

  # Delete orphaned executables left behind in these bundles' Contents/MacOS/
  # by earlier builds under a different branding config (e.g. a stale
  # thin-arch "W3Ai GPU Helper" sitting next to the actual universal-arch
  # "Nightly GPU Helper" that CFBundleExecutable still points to). --deep
  # signing in Step 3 below signs every Mach-O it finds in the bundle, so an
  # undeclared orphan still picks up the shared application-identifier
  # entitlement despite not being the bundle's real identity — exactly the
  # shape of Transporter errors 90049/90885. Keep only the file Info.plist
  # actually declares as CFBundleExecutable.
  for _hname in gpu-helper.app media-plugin-helper.app security-module-helper.app callback_app.app; do
    _hplist="$app_path/Contents/MacOS/$_hname/Contents/Info.plist"
    [ -f "$_hplist" ] || continue
    _hexe="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$_hplist" 2>/dev/null)"
    [ -n "$_hexe" ] || continue
    while IFS= read -r -d '' _horphan; do
      [ "$(basename "$_horphan")" = "$_hexe" ] && continue
      note "Removing orphaned undeclared executable: $_horphan"
      rm -f "$_horphan"
    done < <(find "$app_path/Contents/MacOS/$_hname/Contents/MacOS" -maxdepth 1 -type f -print0 2>/dev/null)
  done

  # Embed a copy of the main app's provisioning profile in the four
  # shared-identity helpers (they use the main app's own identifier, so the
  # main profile already covers them — Transporter's sandbox validation has
  # been unreliable about accepting that by inheritance alone, cheap to embed
  # directly). updater.app is handled separately above: it gets its own
  # dedicated profile when APPLE_UPDATER_PROVISIONING_PROFILE is set, or
  # falls back to the main profile here too when it isn't.
  if [ "$updater_has_profile" != true ]; then
    copy_profile "$main_profile" "$_upd_app"
  fi
  for _shared_app in \
    "$app_path/Contents/MacOS/gpu-helper.app" \
    "$app_path/Contents/MacOS/media-plugin-helper.app" \
    "$app_path/Contents/MacOS/security-module-helper.app" \
    "$app_path/Contents/MacOS/callback_app.app"; do
    [ -d "$_shared_app" ] && copy_profile "$main_profile" "$_shared_app"
  done

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

  # Re-brand the two nested frameworks' org.mozilla.* CFBundleIdentifiers.
  # These never carry application-identifier/provisioning (frameworks are
  # loaded in-process, not independently provisioned), so this is a pure
  # branding fix, not a signing-identity one — but a leftover org.mozilla.*
  # identifier in a com.tmrw.w3ai-signed bundle is still the same red flag
  # for App Store review as every other org.mozilla.* leftover fixed above.
  for _fwpair in \
    "$app_path/Contents/Frameworks/ChannelPrefs.framework=com.tmrw.w3ai.channelprefs" \
    "$app_path/Contents/MacOS/updater.app/Contents/Frameworks/UpdateSettings.framework=com.tmrw.w3ai.updatesettings"; do
    _fwdir="${_fwpair%%=*}"
    _fwid="${_fwpair##*=}"
    _fwplist="$(find "$_fwdir" -path "*/Resources/Info.plist" 2>/dev/null | head -1)"
    if [ -n "$_fwplist" ] && [ -f "$_fwplist" ]; then
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $_fwid" "$_fwplist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $_fwid" "$_fwplist"
      note "Patched $(basename "$_fwdir") bundle ID → $_fwid"
    fi
  done

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

  # Step 3: Sign nested .app bundles. Required order: updater.app first,
  # plugin-container.app second, main TMRW.app last — Transporter scans every
  # nested .app bundle, so each must be fully signed/provisioned (identifier +
  # embedded profile in place) before the parent app seals over it.
  note "Signing updater.app (first — see required signing order)"
  if [ "$updater_has_profile" = true ]; then
    sign_bundle "$_upd_app" "$tmp_upd_ent"
  else
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_shared_id_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$_upd_app"
  fi

  note "Signing remaining shared-identity helper apps..."
  local _cr_has_profile=false
  [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ] && _cr_has_profile=true

  while IFS= read -r nested; do
    [[ "$nested" == "$app_path" ]]   && continue
    [[ "$nested" == "$plugin_app" ]] && continue  # handled separately below
    [[ "$nested" == "$cr_app" ]]     && continue  # handled separately below
    [[ "$nested" == "$_upd_app" ]]   && continue  # already signed above, first
    local nested_name
    nested_name="$(basename "$nested")"
    note "  $nested_name"
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_shared_id_ent" \
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

  note "Signing plugin-container.app (second — see required signing order)"
  sign_bundle "$plugin_app" "$tmp_plugin_ent"

  # Step 4: Seal the main bundle last (no --deep; inner code already signed above)
  note "Signing main TMRW.app (last — see required signing order)"
  sign_bundle "$app_path" "$tmp_main_ent"

  note "Verifying signed bundles"
  [ -n "$crashreporter_profile" ] && [ -f "$crashreporter_profile" ] && \
    verify_bundle_profile "$cr_app" "crashreporter.app"
  verify_bundle_profile "$plugin_app" "plugin-container.app"
  verify_bundle_profile "$app_path" "TMRW.app"
  verify_bundle_profile "$_upd_app" "updater.app"
  for _hname in gpu-helper.app media-plugin-helper.app security-module-helper.app callback_app.app; do
    _hbundle="$app_path/Contents/MacOS/$_hname"
    [ -d "$_hbundle" ] && verify_bundle_profile "$_hbundle" "$_hname"
  done

  note "Verifying nested bundle identifiers match their code signatures"
  verify_identifier_match "$_upd_app" "updater.app"
  verify_identifier_match "$_cr_app" "crashreporter.app"
  for _hname in gpu-helper.app media-plugin-helper.app security-module-helper.app callback_app.app; do
    _hbundle="$app_path/Contents/MacOS/$_hname"
    [ -d "$_hbundle" ] && verify_identifier_match "$_hbundle" "$_hname"
  done

  note "Scanning for orphaned application-identifier entitlements (Transporter 90885)"
  verify_no_orphan_appid "$app_path"

  note "Scanning for undeclared executables in nested .app bundles (Transporter 90049/90885)"
  verify_no_undeclared_executable "$app_path"

  # Final pre-productbuild validation: exact bundle-id checks + embedded
  # provisioning profile existence for the three bundles Transporter is known
  # to scan as nested apps. Deliberately explicit/literal (not routed through
  # verify_identifier_match) so a mismatch names precisely which bundle and
  # which expected value failed, right before packaging.
  note "Validating bundle identifiers before productbuild"
  local _check_main_id _check_plugin_id _check_upd_id
  _check_main_id="$(plist_get "$app_plist" CFBundleIdentifier)"
  [ "$_check_main_id" = "$APPLE_BUNDLE_ID" ] || \
    fail "Main app CFBundleIdentifier is '$_check_main_id', expected '$APPLE_BUNDLE_ID'"
  note "  Main app bundle id OK: $_check_main_id"

  _check_plugin_id="$(plist_get "$plugin_plist" CFBundleIdentifier)"
  [ "$_check_plugin_id" = "$APPLE_PLUGIN_CONTAINER_BUNDLE_ID" ] || \
    fail "plugin-container.app CFBundleIdentifier is '$_check_plugin_id', expected '$APPLE_PLUGIN_CONTAINER_BUNDLE_ID'"
  note "  Plugin-container bundle id OK: $_check_plugin_id"

  _check_upd_id="$(plist_get "$_upd_plist" CFBundleIdentifier)"
  [ "$_check_upd_id" = "$updater_bundle_id" ] || \
    fail "updater.app CFBundleIdentifier is '$_check_upd_id', expected '$updater_bundle_id'"
  note "  Updater bundle id OK: $_check_upd_id"

  note "Validating embedded provisioning profiles before productbuild"
  [ -f "$app_path/Contents/embedded.provisionprofile" ] || \
    fail "Missing $app_path/Contents/embedded.provisionprofile"
  [ -f "$plugin_app/Contents/embedded.provisionprofile" ] || \
    fail "Missing $plugin_app/Contents/embedded.provisionprofile"
  [ -f "$_upd_app/Contents/embedded.provisionprofile" ] || \
    fail "Missing $_upd_app/Contents/embedded.provisionprofile"
  note "  All required embedded.provisionprofile files present"

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
