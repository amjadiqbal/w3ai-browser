#!/usr/bin/env bash
set -euo pipefail

# Package TMRW.app for Mac TestFlight/App Store Connect.
#
# This script reads signing/package settings from .env by default so Apple
# secrets and local signing paths stay in one place. Environment variables
# passed directly to this command still override .env values.
#
# Main .env variables:
#   APP_VERSION=1.2.11                                      # required — no hardcoded fallback
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
# updater.app is deliberately NOT shipped in this (TestFlight/App Store) build —
# App Store handles updates; the in-app MAR updater is only for the direct-DMG
# distribution build (scripts/notarize.sh). It's removed from BUILT_APP_PATH
# before signing, and its absence is verified before AND after productbuild.
#
# crashreporter.app is likewise NOT shipped — Apple/TestFlight already collects
# crash reports, and the Gecko crash reporter binary crashed at launch on
# device (EXC_BAD_INSTRUCTION / SIGILL, SYSCALL_SET_USERLAND_PROFILE — it
# fails during its own sandbox/profile initialization under App Store
# sandboxing) plus showed a Gatekeeper "differs from previously opened
# versions" warning from leftover Nightly/Mozilla strings baked into the
# compiled binary — the same class of problem that got updater.app removed.
# Same treatment: removed before signing, absence verified before AND after
# productbuild. This only applies to this script — direct-DMG builds
# (scripts/notarize.sh) keep shipping crashreporter.app unchanged.
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

# updater.app kept failing App Store review across many rounds (409, 90049,
# 90885, CFBundleIdentifier collision, then 90049 again even with a dedicated
# provisioning profile — `strings` on the shipped binary still showed raw
# Mozilla updater internals: org.mozilla.updater.server,
# /Library/PrivilegedHelperTools/org.mozilla.updater,
# /Library/LaunchDaemons/org.mozilla.updater.plist). App Store builds don't
# need it at all — App Store handles updates, the in-app MAR updater is only
# for the direct-DMG build — so it's simplest and most robust to not ship it
# rather than keep re-branding around baked-in Mozilla internals. These two
# checks make that verifiable rather than assumed.
verify_no_updater_in_source() {
  local app_path="$1"
  if [ -d "$app_path/Contents/MacOS/updater.app" ]; then
    echo "ERROR: updater.app must not be shipped in TestFlight/App Store build" >&2
    exit 1
  fi
  if find "$app_path" -iname "*updater*" | grep -q .; then
    echo "ERROR: updater artifacts still exist in TestFlight/App Store build:" >&2
    find "$app_path" -iname "*updater*" -print >&2
    exit 1
  fi
  note "  No updater.app or updater artifacts in source app bundle"
}

verify_no_updater_in_pkg() {
  local pkg_path="$1"
  local expand_dir="/tmp/tmrw-pkg-check"

  rm -rf "$expand_dir"
  pkgutil --expand-full "$pkg_path" "$expand_dir" || \
    fail "pkgutil --expand-full failed on $pkg_path"

  if find "$expand_dir" -iname "*updater*" | grep -q .; then
    echo "ERROR: updater artifacts exist in final pkg payload:" >&2
    find "$expand_dir" -iname "*updater*" -print >&2
    exit 1
  fi
  note "  No updater artifacts in final pkg payload"
}

# crashreporter.app crashed at launch on-device after a real TestFlight
# install (EXC_BAD_INSTRUCTION / SIGILL, asi signature
# SYSCALL_SET_USERLAND_PROFILE — it fails during its own sandbox/profile
# initialization under App Store sandboxing) and also triggered a Gatekeeper
# "differs from previously opened versions" warning from leftover Nightly/
# Mozilla strings baked into the compiled binary — the same shape of problem
# that got updater.app removed. Apple/TestFlight already collects crash
# reports on its own, so there's no need to ship Gecko's crash reporter in
# this build at all. These two checks make its absence verifiable.
verify_no_crashreporter_in_source() {
  local app_path="$1"
  if find "$app_path" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) | grep -q .; then
    echo "ERROR: crash reporter artifacts must not be shipped in TestFlight/App Store build" >&2
    find "$app_path" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) -print >&2
    exit 1
  fi
  note "  No crash reporter artifacts in source app bundle"
}

verify_no_crashreporter_in_pkg() {
  local expand_dir="$1"

  if find "$expand_dir" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) | grep -q .; then
    echo "ERROR: crash reporter artifacts exist in final pkg payload:" >&2
    find "$expand_dir" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) -print >&2
    exit 1
  fi

  if grep -R "Nightly Crash Reporter\|Mozilla Crash Reporter" "$expand_dir" 2>/dev/null | grep -q .; then
    echo "ERROR: Nightly/Mozilla crash reporter branding found in final pkg" >&2
    exit 1
  fi
  note "  No crash reporter artifacts or Nightly/Mozilla branding in final pkg payload"
}

# `codesign --verify --deep --strict` only checks code signature integrity —
# hashes match, cert chain is valid. It does NOT check whether an embedded
# provisioning profile's application-identifier actually matches what the
# bundle's own CFBundleIdentifier or entitlements claim. That mismatch is
# invisible to every check in this script until macOS enforces it at
# TestFlight *install/launch* time ("The provisioning profile is invalid"),
# which is exactly what happened: gpu-helper.app/media-plugin-helper.app/
# security-module-helper.app/callback_app.app each had a distinct
# CFBundleIdentifier (com.tmrw.w3ai.gpu-helper etc, from the earlier
# CFBundleIdentifier-collision fix) but were embedded with the MAIN app's
# provisioning profile (covers K9B6ZLA9M4.com.tmrw.w3ai, not
# K9B6ZLA9M4.com.tmrw.w3ai.gpu-helper) — internally self-consistent by every
# check this script had (identifier matches signature, profile file exists,
# codesign --verify passes) but wrong the moment the OS actually checks
# profile-to-identity binding rather than just signature validity.
#
# Scans every nested .app bundle under $1 (root can be BUILT_APP_PATH or an
# expanded pkg's Payload/TMRW.app) and checks A-I below. Any failure prints a
# precise "expected X, got Y" message and hard-fails packaging.
audit_app_bundle_profile_and_signature() {
  local root="$1"
  local label="$2"
  local bundle plist bundle_id bundle_exe sig_id sig_team ent_file ent_appid
  local profile_file profile_plist profile_appid profile_team profile_exp profile_exp_epoch now_epoch
  local failures=0

  note "Auditing bundle/profile/signature consistency ($label)"

  while IFS= read -r bundle; do
    plist="$bundle/Contents/Info.plist"
    [ -f "$plist" ] || continue

    bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)"
    bundle_exe="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)"

    # A. CFBundleIdentifier must not be empty.
    if [ -z "$bundle_id" ]; then
      echo "ERROR: $bundle has an empty CFBundleIdentifier" >&2
      failures=$((failures + 1))
      continue
    fi

    sig_id="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^Identifier=//p' || true)"
    sig_team="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"

    # B. codesign Identifier must equal CFBundleIdentifier.
    if [ "$sig_id" != "$bundle_id" ]; then
      echo "ERROR: $bundle ($bundle_exe) codesign Identifier '$sig_id' does not match CFBundleIdentifier '$bundle_id'" >&2
      failures=$((failures + 1))
    fi

    # C. codesign TeamIdentifier must equal the configured team.
    if [ "$sig_team" != "$APPLE_TEAM_ID" ]; then
      echo "ERROR: $bundle ($bundle_exe) codesign TeamIdentifier '$sig_team' does not match expected '$APPLE_TEAM_ID'" >&2
      failures=$((failures + 1))
    fi

    ent_file="$(mktemp /tmp/audit-entitlements.XXXXXX)"
    codesign -d --entitlements :- "$bundle" > "$ent_file" 2>/dev/null || true
    ent_appid=""
    if [ -s "$ent_file" ]; then
      ent_appid="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$ent_file" 2>/dev/null || true)"
    fi

    # D. If entitlements carry application-identifier, it must equal
    # TEAMID.<CFBundleIdentifier> — exactly this bundle's own identity, never
    # a different bundle's (e.g. the main app's, when this bundle isn't main).
    if [ -n "$ent_appid" ] && [ "$ent_appid" != "${APPLE_TEAM_ID}.${bundle_id}" ]; then
      echo "ERROR: $bundle ($bundle_exe) entitlements application-identifier is '$ent_appid', expected '${APPLE_TEAM_ID}.${bundle_id}'" >&2
      failures=$((failures + 1))
    fi
    rm -f "$ent_file"

    profile_file="$bundle/Contents/embedded.provisionprofile"
    if [ -f "$profile_file" ]; then
      profile_plist="$(mktemp /tmp/audit-profile.XXXXXX)"
      security cms -D -i "$profile_file" > "$profile_plist" 2>/dev/null || true
      profile_appid="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$profile_plist" 2>/dev/null || true)"
      profile_team="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$profile_plist" 2>/dev/null || true)"
      profile_exp="$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$profile_plist" 2>/dev/null || true)"

      # E/I. Profile's application-identifier must match THIS bundle's own
      # identity — the exact mismatch class that broke TestFlight runtime
      # provisioning: a profile that actually covers a *different* bundle's
      # identifier (typically the main app's) embedded into this one instead.
      if [ "$profile_appid" != "${APPLE_TEAM_ID}.${bundle_id}" ]; then
        echo "ERROR: $bundle ($bundle_exe) profile app id '$profile_appid' does not match bundle id ${APPLE_TEAM_ID}.${bundle_id}" >&2
        echo "  Expected profile app id ${APPLE_TEAM_ID}.${bundle_id}" >&2
        failures=$((failures + 1))
      fi

      # F. Profile team id must equal the configured team.
      if [ "$profile_team" != "$APPLE_TEAM_ID" ]; then
        echo "ERROR: $bundle ($bundle_exe) profile team id '$profile_team' does not match expected '$APPLE_TEAM_ID'" >&2
        failures=$((failures + 1))
      fi

      # G. Profile must not be expired.
      if [ -n "$profile_exp" ]; then
        profile_exp_epoch="$(date -j -f "%a %b %d %T %Z %Y" "$profile_exp" "+%s" 2>/dev/null || echo 0)"
        now_epoch="$(date "+%s")"
        if [ "$profile_exp_epoch" -gt 0 ] && [ "$profile_exp_epoch" -lt "$now_epoch" ]; then
          echo "ERROR: $bundle ($bundle_exe) embedded provisioning profile expired on $profile_exp" >&2
          failures=$((failures + 1))
        fi
      fi

      # H (profile-present side): entitlements app id, if present, must agree
      # with what the profile actually covers too — catches the case where
      # entitlements and profile agree with each other but neither matches
      # CFBundleIdentifier (exactly what happened with the shared-identity
      # helpers: entitlements said K9B6ZLA9M4.com.tmrw.w3ai, profile also said
      # K9B6ZLA9M4.com.tmrw.w3ai, but the bundle's own id was
      # com.tmrw.w3ai.gpu-helper).
      if [ -n "$ent_appid" ] && [ "$ent_appid" != "$profile_appid" ]; then
        echo "ERROR: $bundle ($bundle_exe) entitlements application-identifier '$ent_appid' does not match embedded profile application-identifier '$profile_appid'" >&2
        failures=$((failures + 1))
      fi
      rm -f "$profile_plist"
    else
      # H (no-profile side): an application-identifier entitlement with no
      # embedded profile to back it is the exact shape of Transporter 90885.
      if [ -n "$ent_appid" ]; then
        echo "ERROR: $bundle ($bundle_exe) has entitlements application-identifier '$ent_appid' but no Contents/embedded.provisionprofile" >&2
        failures=$((failures + 1))
      fi
    fi

    if [ -z "$ent_appid" ] && [ ! -f "$profile_file" ]; then
      note "  $bundle_exe ($bundle_id): no application-identifier, no embedded profile — OK"
    else
      note "  $bundle_exe ($bundle_id): application-identifier and profile consistent"
    fi
  done < <(find "$root" -name "*.app" -type d)

  if [ "$failures" -gt 0 ]; then
    fail "$failures bundle/profile/signature audit failure(s) found in $label — see errors above"
  fi
  note "  Audit clean: every bundle's CFBundleIdentifier, code signature, entitlements, and embedded profile agree ($label)"
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

  # Bypass App Store Connect export compliance dialog — standard TLS algorithms only
  /usr/libexec/PlistBuddy -c "Delete :ITSAppUsesNonExemptEncryption" "$app_plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$app_plist"

  note "Setting main bundle id to $APPLE_BUNDLE_ID"
  plist_set "$app_plist" CFBundleIdentifier "$APPLE_BUNDLE_ID"

  note "Setting plugin-container bundle id to $APPLE_PLUGIN_CONTAINER_BUNDLE_ID"
  plist_set "$plugin_plist" CFBundleIdentifier "$APPLE_PLUGIN_CONTAINER_BUNDLE_ID"

  note "Main bundle id: $(plist_get "$app_plist" CFBundleIdentifier)"
  note "Plugin bundle id: $(plist_get "$plugin_plist" CFBundleIdentifier)"

  # Remove updater.app and every updater-related artifact entirely for this
  # TestFlight/App Store build. This does NOT apply to the direct-DMG build
  # (scripts/notarize.sh) — only this script. Must happen after the app is
  # fully built/copied into BUILT_APP_PATH but before any signing, so nothing
  # downstream (entitlements, profile embedding, codesign) ever touches it.
  note "Removing updater.app and updater artifacts (not shipped in App Store builds)"
  rm -rf "$app_path/Contents/MacOS/updater.app"
  rm -f "$app_path/Contents/Resources/updater.ini"
  rm -f "$app_path/Contents/Resources/update-settings.ini"
  rm -f "$app_path/Contents/Resources/org.mozilla.updater"
  rm -f "$app_path/Contents/Resources/TMRWUpdater"
  rm -f "$app_path/Contents/Library/LaunchServices/org.mozilla.updater"
  rm -f "$app_path/Contents/Library/LaunchServices/TMRWUpdater"
  while IFS= read -r _leftover; do
    note "  Removing leftover updater artifact: $_leftover"
    rm -rf "$_leftover"
  done < <(find "$app_path" -iname "*updater*")
  verify_no_updater_in_source "$app_path"

  # Remove crashreporter.app and every crash-reporter-related artifact
  # entirely for this TestFlight/App Store build — same treatment and same
  # reasoning as updater.app above. Direct-DMG builds (scripts/notarize.sh)
  # are untouched and keep shipping crashreporter.app unchanged.
  note "Removing crashreporter.app and crash reporter artifacts (not shipped in App Store builds)"
  rm -rf "$app_path/Contents/MacOS/crashreporter.app"
  rm -f "$app_path/Contents/MacOS/crashreporter"
  rm -f "$app_path/Contents/MacOS/crashhelper"
  rm -f "$app_path/Contents/Resources/crashreporter.ini"
  rm -f "$app_path/Contents/Resources/browser/crashreporter.ini"
  while IFS= read -r _leftover; do
    note "  Removing leftover crash reporter artifact: $_leftover"
    rm -rf "$_leftover"
  done < <(find "$app_path" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \))
  verify_no_crashreporter_in_source "$app_path"

  note "Embedding provisioning profiles"
  copy_profile "$main_profile" "$app_path"
  copy_profile "$plugin_profile" "$plugin_app"

  # Build temp entitlements with application-identifier injected
  local main_app_id="${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}"
  local plugin_app_id="${APPLE_TEAM_ID}.${APPLE_PLUGIN_CONTAINER_BUNDLE_ID}"
  local tmp_main_ent tmp_plugin_ent tmp_helper_ent tmp_shared_id_ent
  tmp_main_ent=""
  tmp_plugin_ent=""
  tmp_helper_ent=""
  tmp_shared_id_ent=""
  trap 'rm -f "${tmp_main_ent:-}" "${tmp_plugin_ent:-}" "${tmp_helper_ent:-}" "${tmp_shared_id_ent:-}"' EXIT
  tmp_main_ent="$(make_entitlements_with_appid "$main_entitlements" "$main_app_id" "$APPLE_TEAM_ID")"
  tmp_plugin_ent="$(make_entitlements_with_appid "$plugin_entitlements" "$plugin_app_id" "$APPLE_TEAM_ID")"

  # Generic entitlements for loose (non-bundle) Mach-O files and frameworks —
  # dylibs, standalone tools (ssltunnel, certutil, pingsender...),
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

  # Entitlements for gpu-helper.app, media-plugin-helper.app,
  # security-module-helper.app, callback_app.app: sandboxed, but deliberately
  # NO application-identifier and NO embedded provisioning profile.
  #
  # This used to give them application-identifier = TEAMID.com.tmrw.w3ai (the
  # MAIN app's identity) plus a copy of the main app's own embedded profile —
  # while each bundle's own CFBundleIdentifier is distinct
  # (com.tmrw.w3ai.gpu-helper etc, needed to avoid the CFBundleIdentifier
  # Collision Transporter rejects). That mismatch (profile covers
  # TEAMID.com.tmrw.w3ai, bundle claims to be com.tmrw.w3ai.gpu-helper) passed
  # every check this script had — codesign --verify only checks signature
  # integrity, not whether the embedded profile's identity actually matches
  # the bundle claiming it — but macOS enforces it at TestFlight install/
  # launch time: "The provisioning profile is invalid." None of these four
  # have a dedicated Apple Developer App ID, so the only fix that doesn't
  # require new Apple Developer Portal registrations is to not claim an
  # application-identifier at all — a plain sandboxed helper needs no
  # provisioned identity of its own to run inside its parent's sandbox.
  # See audit_app_bundle_profile_and_signature() above, which is exactly the
  # check that would have caught this the first time.
  tmp_shared_id_ent="$(mktemp /tmp/entitlements-shared-id.XXXXXX)"
  cat > "$tmp_shared_id_ent" <<'ENTXML'
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

  # Re-brand remaining org.mozilla.* helper bundle IDs. Each gets its own
  # distinct CFBundleIdentifier — NOT the main app's exact identifier, which
  # Apple's App Store validator rejects as a "CFBundleIdentifier Collision".
  # Their *entitlements* application-identifier (tmp_shared_id_ent) still
  # points at the main app's shared identity/profile, since none of them have
  # their own Apple Developer App ID — that field is independent of
  # CFBundleIdentifier.
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

  # Deliberately do NOT embed any provisioning profile in gpu-helper.app,
  # media-plugin-helper.app, security-module-helper.app, callback_app.app —
  # see the tmp_shared_id_ent comment above for why (embedding the main app's
  # profile into a bundle with a different CFBundleIdentifier is exactly what
  # broke TestFlight runtime provisioning). Actively remove any stale one a
  # previous run of this script may have left behind, so re-running against
  # an already-mutated BUILT_APP_PATH doesn't leave a leftover mismatched
  # profile in place.
  for _shared_app in \
    "$app_path/Contents/MacOS/gpu-helper.app" \
    "$app_path/Contents/MacOS/media-plugin-helper.app" \
    "$app_path/Contents/MacOS/security-module-helper.app" \
    "$app_path/Contents/MacOS/callback_app.app"; do
    [ -d "$_shared_app" ] && rm -f "$_shared_app/Contents/embedded.provisionprofile"
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

  # Re-brand the nested framework's org.mozilla.* CFBundleIdentifier. Never
  # carries application-identifier/provisioning (frameworks are loaded
  # in-process, not independently provisioned), so this is a pure branding
  # fix, not a signing-identity one — but a leftover org.mozilla.* identifier
  # in a com.tmrw.w3ai-signed bundle is still the same red flag for App Store
  # review as every other org.mozilla.* leftover fixed above.
  for _fwpair in \
    "$app_path/Contents/Frameworks/ChannelPrefs.framework=com.tmrw.w3ai.channelprefs"; do
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
  # plugin-container flat binary, etc. — updater.app and its loose copies were
  # already removed earlier and are never reached here) — the full set that
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

  # Step 2: Sign loose Mach-O executables in MacOS/ (XUL, pingsender... —
  # crashhelper was already removed earlier and is never reached here)
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

  # Step 3: Sign nested .app bundles. Required order: plugin-container.app
  # second-to-last, main TMRW.app last — Transporter scans every nested .app
  # bundle, so each must be fully signed/provisioned (identifier + embedded
  # profile in place) before the parent app seals over it. updater.app and
  # crashreporter.app were both removed entirely earlier in this script, so
  # neither is ever reached here.
  note "Signing shared-identity helper apps..."
  while IFS= read -r nested; do
    [[ "$nested" == "$app_path" ]]   && continue
    [[ "$nested" == "$plugin_app" ]] && continue  # handled separately below
    local nested_name
    nested_name="$(basename "$nested")"
    note "  $nested_name"
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$tmp_shared_id_ent" \
      --sign "$APPLE_SIGNING_IDENTITY" "$nested"
  done < <(find "$app_path/Contents" -name "*.app" -type d | sort -r)

  note "Signing plugin-container.app (second — see required signing order)"
  sign_bundle "$plugin_app" "$tmp_plugin_ent"

  # Step 4: Seal the main bundle last (no --deep; inner code already signed above)
  note "Signing main TMRW.app (last — see required signing order)"
  sign_bundle "$app_path" "$tmp_main_ent"

  note "Verifying signed bundles"
  verify_bundle_profile "$plugin_app" "plugin-container.app"
  verify_bundle_profile "$app_path" "TMRW.app"
  # No verify_bundle_profile for the 4 shared helpers — they deliberately have
  # no embedded.provisionprofile now (see tmp_shared_id_ent comment above),
  # so that check would always fail. Plain signature verification still
  # applies.
  for _hname in gpu-helper.app media-plugin-helper.app security-module-helper.app callback_app.app; do
    _hbundle="$app_path/Contents/MacOS/$_hname"
    if [ -d "$_hbundle" ]; then
      codesign --verify --deep --strict --verbose=2 "$_hbundle"
    fi
  done

  note "Verifying nested bundle identifiers match their code signatures"
  for _hname in gpu-helper.app media-plugin-helper.app security-module-helper.app callback_app.app; do
    _hbundle="$app_path/Contents/MacOS/$_hname"
    [ -d "$_hbundle" ] && verify_identifier_match "$_hbundle" "$_hname"
  done

  note "Scanning for orphaned application-identifier entitlements (Transporter 90885)"
  verify_no_orphan_appid "$app_path"

  note "Scanning for undeclared executables in nested .app bundles (Transporter 90049/90885)"
  verify_no_undeclared_executable "$app_path"

  # Final pre-productbuild validation: exact bundle-id checks + embedded
  # provisioning profile existence for the bundles Transporter is known to
  # scan as nested apps. Deliberately explicit/literal (not routed through
  # verify_identifier_match) so a mismatch names precisely which bundle and
  # which expected value failed, right before packaging. Also re-confirms
  # updater.app/crashreporter.app and their artifacts are still absent —
  # mandatory, not just a one-time check earlier in the script.
  note "Validating bundle identifiers before productbuild"
  local _check_main_id _check_plugin_id
  _check_main_id="$(plist_get "$app_plist" CFBundleIdentifier)"
  [ "$_check_main_id" = "$APPLE_BUNDLE_ID" ] || \
    fail "Main app CFBundleIdentifier is '$_check_main_id', expected '$APPLE_BUNDLE_ID'"
  note "  Main app bundle id OK: $_check_main_id"

  _check_plugin_id="$(plist_get "$plugin_plist" CFBundleIdentifier)"
  [ "$_check_plugin_id" = "$APPLE_PLUGIN_CONTAINER_BUNDLE_ID" ] || \
    fail "plugin-container.app CFBundleIdentifier is '$_check_plugin_id', expected '$APPLE_PLUGIN_CONTAINER_BUNDLE_ID'"
  note "  Plugin-container bundle id OK: $_check_plugin_id"

  note "Validating embedded provisioning profiles before productbuild"
  [ -f "$app_path/Contents/embedded.provisionprofile" ] || \
    fail "Missing $app_path/Contents/embedded.provisionprofile"
  [ -f "$plugin_app/Contents/embedded.provisionprofile" ] || \
    fail "Missing $plugin_app/Contents/embedded.provisionprofile"
  note "  All required embedded.provisionprofile files present"

  note "Validating updater.app is absent before productbuild"
  verify_no_updater_in_source "$app_path"

  note "Validating crash reporter artifacts are absent before productbuild"
  verify_no_crashreporter_in_source "$app_path"

  # Mandatory: every nested .app's CFBundleIdentifier, code signature,
  # entitlements, and embedded provisioning profile must all actually agree
  # with each other — not just individually pass codesign --verify. This is
  # what codesign --verify structurally cannot catch (see function comment).
  audit_app_bundle_profile_and_signature "$app_path" "BUILT_APP_PATH pre-productbuild"

  local pkg_path="$out_dir/$TESTFLIGHT_PKG_NAME"
  rm -f "$pkg_path"

  note "Building pkg: $pkg_path"
  productbuild --component "$app_path" /Applications --sign "$APPLE_INSTALLER_IDENTITY" "$pkg_path"

  note "Verifying pkg signature"
  pkgutil --check-signature "$pkg_path"
  xcrun stapler validate "$pkg_path" >/dev/null 2>&1 || true

  note "Validating updater.app is absent from the shipped pkg (post-productbuild)"
  verify_no_updater_in_pkg "$pkg_path"

  note "Validating crash reporter artifacts are absent from the shipped pkg (post-productbuild)"
  verify_no_crashreporter_in_pkg "/tmp/tmrw-pkg-check"

  note "Re-auditing bundle/profile/signature consistency against the actual shipped payload"
  local _expand_dir="/tmp/tmrw-pkg-check"
  local _shipped_app
  _shipped_app="$(find "$_expand_dir" -maxdepth 4 -name "TMRW.app" -type d | head -1)"
  [ -n "$_shipped_app" ] && [ -d "$_shipped_app" ] || \
    fail "Could not find TMRW.app in expanded pkg payload at $_expand_dir"
  audit_app_bundle_profile_and_signature "$_shipped_app" "shipped pkg payload post-productbuild"

  # The expanded payload (several hundred MB) was only needed for the checks
  # above — left in place it silently accumulates on /tmp on every single
  # run, which is exactly what emptied the boot disk and corrupted a pkg
  # build outright on 2026-07-05 (productbuild failed mid-write with ENOSPC).
  rm -rf "$_expand_dir"

  note "Done: $pkg_path"
}

main "$@"
