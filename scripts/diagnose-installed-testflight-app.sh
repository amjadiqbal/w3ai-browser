#!/usr/bin/env bash
# diagnose-installed-testflight-app.sh — inspect an already-installed TMRW.app
# (e.g. one delivered via TestFlight) for the exact class of bug that causes
# "The beta app is no longer available. The provisioning profile is invalid."
# at launch time, even though it uploaded/installed successfully.
#
# codesign --verify only checks signature integrity — it does NOT check
# whether a bundle's embedded provisioning profile actually covers that
# bundle's own CFBundleIdentifier. A profile that's valid and correctly
# signed but belongs to a *different* bundle passes codesign --verify and
# still gets rejected by macOS at install/launch time. This script reads and
# cross-checks the same fields scripts/package-testflight-macos.sh does at
# build time (see audit_app_bundle_profile_and_signature there), but against
# a real installed app instead of the pre-productbuild source tree.
#
# Usage:
#   ./scripts/diagnose-installed-testflight-app.sh                # /Applications/TMRW.app
#   ./scripts/diagnose-installed-testflight-app.sh /path/to/TMRW.app

set -uo pipefail

APP_PATH="${1:-/Applications/TMRW.app}"
TEAM_ID="${APPLE_TEAM_ID:-K9B6ZLA9M4}"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_PATH does not exist" >&2
  exit 1
fi

echo "==> Diagnosing $APP_PATH (expected team id: $TEAM_ID)"
echo ""

total=0
failed=0

while IFS= read -r bundle; do
  plist="$bundle/Contents/Info.plist"
  [ -f "$plist" ] || continue
  total=$((total + 1))

  bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)"
  bundle_exe="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null || true)"
  sig_id="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^Identifier=//p' || true)"
  sig_team="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"

  ent_file="$(mktemp /tmp/diagnose-entitlements.XXXXXX)"
  codesign -d --entitlements :- "$bundle" > "$ent_file" 2>/dev/null || true
  ent_appid=""
  [ -s "$ent_file" ] && ent_appid="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$ent_file" 2>/dev/null || true)"
  rm -f "$ent_file"

  profile_file="$bundle/Contents/embedded.provisionprofile"
  profile_appid=""
  profile_team=""
  profile_exp=""
  has_profile=false
  if [ -f "$profile_file" ]; then
    has_profile=true
    profile_plist="$(mktemp /tmp/diagnose-profile.XXXXXX)"
    security cms -D -i "$profile_file" > "$profile_plist" 2>/dev/null || true
    profile_appid="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$profile_plist" 2>/dev/null || true)"
    profile_team="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$profile_plist" 2>/dev/null || true)"
    profile_exp="$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$profile_plist" 2>/dev/null || true)"
    rm -f "$profile_plist"
  fi

  echo "── $bundle"
  echo "   CFBundleIdentifier:        ${bundle_id:-<empty>}"
  echo "   CFBundleExecutable:        ${bundle_exe:-<empty>}"
  echo "   codesign Identifier:       ${sig_id:-<empty>}"
  echo "   codesign TeamIdentifier:   ${sig_team:-<empty>}"
  echo "   entitlements app id:       ${ent_appid:-<none>}"
  if [ "$has_profile" = true ]; then
    echo "   embedded profile app id:   ${profile_appid:-<empty>}"
    echo "   embedded profile team id:  ${profile_team:-<empty>}"
    echo "   embedded profile expires:  ${profile_exp:-<unknown>}"
  else
    echo "   embedded profile:          <none>"
  fi

  bundle_failed=false
  [ -z "$bundle_id" ] && bundle_failed=true
  [ -n "$bundle_id" ] && [ "$sig_id" != "$bundle_id" ] && bundle_failed=true
  [ "$sig_team" != "$TEAM_ID" ] && bundle_failed=true
  if [ -n "$ent_appid" ] && [ -n "$bundle_id" ] && [ "$ent_appid" != "${TEAM_ID}.${bundle_id}" ]; then
    bundle_failed=true
  fi
  if [ "$has_profile" = true ] && [ -n "$bundle_id" ] && [ "$profile_appid" != "${TEAM_ID}.${bundle_id}" ]; then
    bundle_failed=true
  fi
  if [ "$has_profile" = true ] && [ "$profile_team" != "$TEAM_ID" ]; then
    bundle_failed=true
  fi
  if [ -n "$ent_appid" ] && [ "$has_profile" != true ]; then
    bundle_failed=true
  fi
  if [ "$has_profile" = true ] && [ -n "$profile_exp" ]; then
    profile_exp_epoch="$(date -j -f "%a %b %d %T %Z %Y" "$profile_exp" "+%s" 2>/dev/null || echo 0)"
    now_epoch="$(date "+%s")"
    if [ "$profile_exp_epoch" -gt 0 ] && [ "$profile_exp_epoch" -lt "$now_epoch" ]; then
      bundle_failed=true
    fi
  fi

  if [ "$bundle_failed" = true ]; then
    echo "   RESULT: FAIL"
    failed=$((failed + 1))
  else
    echo "   RESULT: PASS"
  fi
  echo ""
done < <(find "$APP_PATH" -name "*.app" -type d)

echo "==> $((total - failed))/$total bundles passed"
if [ "$failed" -gt 0 ]; then
  echo "==> $failed bundle(s) FAILED — this is the likely cause of \"The provisioning profile is invalid\""
  exit 1
fi
echo "==> All bundles consistent"
