#!/usr/bin/env bash
# diagnose-testflight-app-resources.sh — inspect a TMRW.app bundle (built or
# installed) for the exact class of bug found 2026-07-05: the app can be
# validly signed and still be missing huge swaths of Gecko chrome/locale/JS
# resources, because codesign only proves the bytes present weren't
# tampered with — never that all the *expected* bytes are actually there.
#
# Usage:
#   ./scripts/diagnose-testflight-app-resources.sh /Applications/TMRW.app
#   ./scripts/diagnose-testflight-app-resources.sh /Volumes/Amjad/Plato/W3Ai/obj-x86_64-apple-darwin25.5.0/dist/TMRW.app

set -uo pipefail

APP_PATH="${1:?Usage: $0 /path/to/TMRW.app}"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_PATH does not exist" >&2
  exit 1
fi

fail_count=0
note() { echo "==> $*"; }
check_fail() { echo "FAIL: $*" >&2; fail_count=$((fail_count + 1)); }

echo "==> Diagnosing $APP_PATH"
echo ""

# ── Version / bundle id / main executable ────────────────────────────────────
note "Basic identity"
PLIST="$APP_PATH/Contents/Info.plist"
if [ -f "$PLIST" ]; then
  echo "   CFBundleShortVersionString: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)"
  echo "   CFBundleVersion:            $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null)"
  echo "   CFBundleIdentifier:         $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)"
  echo "   CFBundleExecutable:         $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)"
else
  check_fail "Missing Contents/Info.plist"
fi
echo ""

# ── Code signature ────────────────────────────────────────────────────────────
note "Code signature"
if codesign -dv "$APP_PATH" 2>&1 | grep -q "^Identifier="; then
  codesign -dv "$APP_PATH" 2>&1 | grep -E "^Identifier=|^TeamIdentifier=|^Authority="
else
  check_fail "codesign could not read a signature from $APP_PATH"
fi
echo ""

# ── MainMenu.nib ──────────────────────────────────────────────────────────────
note "MainMenu.nib"
NIB="$APP_PATH/Contents/Resources/res/MainMenu.nib"
if [ ! -d "$NIB" ]; then
  check_fail "Missing $NIB"
else
  echo "   $(find "$NIB" -maxdepth 1 -type f -print)"
  if ls "$NIB" 2>/dev/null | grep -qE '^(keyedobjects|objects|data)\.nib$'; then
    echo "   Valid: contains a keyedobjects.nib/objects.nib/data.nib"
    file "$NIB"/*.nib 2>/dev/null | sed 's/^/   /'
  else
    check_fail "$NIB exists but is empty/invalid — no keyedobjects.nib, objects.nib, or data.nib inside"
  fi
fi
echo ""

# ── omni.ja (informational only — this build type ships resources loose,
# not jarred, so omni.ja legitimately not existing is not itself a failure) ──
note "omni.ja (informational — this build config does not require one)"
OMNI_ROOT="$APP_PATH/Contents/Resources/omni.ja"
OMNI_BROWSER="$APP_PATH/Contents/Resources/browser/omni.ja"
if [ -f "$OMNI_ROOT" ]; then
  echo "   Contents/Resources/omni.ja: present ($(du -h "$OMNI_ROOT" | cut -f1))"
  unzip -l "$OMNI_ROOT" 2>/dev/null | grep -Ec "profileSelection.properties|brand.properties|css.properties|xul.properties|necko.properties" | \
    xargs -I{} echo "   Contains {} of the expected properties files"
else
  echo "   Contents/Resources/omni.ja: not present (expected for this artifact-build config — resources ship loose instead)"
fi
if [ -f "$OMNI_BROWSER" ]; then
  echo "   Contents/Resources/browser/omni.ja: present ($(du -h "$OMNI_BROWSER" | cut -f1))"
else
  echo "   Contents/Resources/browser/omni.ja: not present (expected for this artifact-build config)"
fi
echo ""

# ── Required chrome/locale resources (loose-file form) ───────────────────────
note "Required chrome/locale resources"
for rel in \
  "chrome/en-US/locale/en-US/mozapps/profile/profileSelection.properties" \
  "chrome/en-US/locale/en-US/global/commonDialogs.properties" \
  "chrome/en-US/locale/en-US/global/css.properties" \
  "chrome/en-US/locale/en-US/global/xul.properties" \
  "chrome/en-US/locale/en-US/global/layout_errors.properties" \
  "chrome/en-US/locale/en-US/global/dom/dom.properties" \
  "chrome/en-US/locale/en-US/necko/necko.properties" \
  "browser/chrome/en-US/locale/branding/brand.properties" \
  "chrome.manifest" \
  "browser/chrome.manifest" \
; do
  f="$APP_PATH/Contents/Resources/$rel"
  if [ -s "$f" ]; then
    echo "   OK   $rel ($(wc -c < "$f" | tr -d ' ') bytes)"
  else
    check_fail "missing or empty: Contents/Resources/$rel"
  fi
done
echo ""

# ── Broader resource directory presence (file counts, not full validation) ──
note "Resource directory file counts (sanity check for wholesale-missing content)"
for d in chrome browser/chrome browser/modules browser/actors browser/localization \
         modules actors localization components res; do
  full="$APP_PATH/Contents/Resources/$d"
  if [ -d "$full" ]; then
    count=$(find "$full" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "   $d: $count files"
    [ "$count" -eq 0 ] && check_fail "$d exists but has zero files — likely wholesale missing content"
  else
    echo "   $d: MISSING ENTIRELY"
  fi
done
echo ""

# ── application.ini / platform.ini ───────────────────────────────────────────
note "application.ini / platform.ini"
for f in "$APP_PATH/Contents/Resources/application.ini" "$APP_PATH/Contents/Resources/platform.ini"; do
  if [ -f "$f" ]; then
    echo "   $(basename "$f"):"
    grep -E "^Vendor=|^Name=|^RemotingName=|^Version=|^BuildID=" "$f" 2>/dev/null | sed 's/^/     /'
  else
    echo "   $(basename "$f"): not present"
  fi
done
echo ""

# ── updater/crashreporter must NOT be present (regression check) ────────────
note "updater/crashreporter regression check (must be absent)"
if find "$APP_PATH" -iname "*updater*" 2>/dev/null | grep -q .; then
  check_fail "updater artifacts found (should have been removed for TestFlight/App Store):"
  find "$APP_PATH" -iname "*updater*" -print
else
  echo "   OK: no updater artifacts"
fi
if find "$APP_PATH" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) 2>/dev/null | grep -q .; then
  check_fail "crash reporter artifacts found (should have been removed for TestFlight/App Store):"
  find "$APP_PATH" \( -iname "*crashreporter*" -o -iname "*crashhelper*" \) -print
else
  echo "   OK: no crash reporter artifacts"
fi
echo ""

# ── Nested .app bundle ids + signatures ──────────────────────────────────────
note "Nested .app bundles"
while IFS= read -r bundle; do
  [ "$bundle" = "$APP_PATH" ] && continue
  bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null)"
  sig="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^Identifier=//p')"
  echo "   $(basename "$bundle"): CFBundleIdentifier=$bid  codesign=$sig $([ "$bid" = "$sig" ] && echo OK || echo MISMATCH)"
  [ "$bid" != "$sig" ] && check_fail "$(basename "$bundle"): CFBundleIdentifier ($bid) != codesign Identifier ($sig)"
done < <(find "$APP_PATH/Contents/MacOS" -name "*.app" -type d 2>/dev/null)
echo ""

echo "==================================================================="
if [ "$fail_count" -gt 0 ]; then
  echo "RESULT: $fail_count check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
