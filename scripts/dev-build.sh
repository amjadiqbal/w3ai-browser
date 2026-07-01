#!/usr/bin/env bash
# Dev build + launch for TMRW Browser artifact builds.
#
# Strategy: use the original UNSIGNED Mozilla artifact binary as the base so
# child processes (tabs, GPU, sockets) spawn without code-signature enforcement.
# Overlay our custom JS/CSS from dist/bin/ on top without any re-signing.
#
# Usage:
#   scripts/dev-build.sh           # build JS + launch browser
#   scripts/dev-build.sh --no-run  # build JS only, skip launch

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
ARTIFACT_DMG="$HOME/.mozbuild/package-frontend/029fef2b78c75561-target.dmg"
WORK_APP="$OBJ_DIR/dist/dev-run.app"
BIN_DIR="$OBJ_DIR/dist/bin"
PROFILE_DIR="$OBJ_DIR/tmp/profile-default"
RUN=true

for arg in "$@"; do
  [[ "$arg" == "--no-run" ]] && RUN=false
done

# ── Step 1: ensure the unsigned Mozilla base app exists ────────────────────
if [[ ! -d "$WORK_APP" ]]; then
  echo "==> First run: copying unsigned Mozilla artifact base..."
  if [[ ! -f "$ARTIFACT_DMG" ]]; then
    echo "ERROR: Artifact DMG not found at $ARTIFACT_DMG"
    echo "Run: ./mach artifact install"
    exit 1
  fi
  MOUNT_VOL=$(ls /Volumes/ | grep -iE "nightly|firefox" | head -1)
  if [[ -z "$MOUNT_VOL" ]]; then
    hdiutil attach "$ARTIFACT_DMG" -nobrowse -quiet 2>/dev/null
    MOUNT_VOL=$(ls /Volumes/ | grep -iE "nightly|firefox" | head -1)
  fi
  cp -a "/Volumes/$MOUNT_VOL/"*.app "$WORK_APP"
  hdiutil detach "/Volumes/$MOUNT_VOL" -quiet 2>/dev/null || true
  xattr -dr com.apple.quarantine "$WORK_APP" 2>/dev/null || true
  echo "    Done."
fi

# ── Step 2: build faster (JS file install) ─────────────────────────────────
echo "==> Installing updated JS/CSS files..."
cd "$REPO_ROOT"
./mach build faster 2>&1 | grep -E "Added/updated|Elapsed" || true

# ── Step 3: overlay TMRW branding onto all dist locations ──────────────────
echo "==> Applying TMRW branding patches..."
BRANDING="$REPO_ROOT/browser/branding/w3ai"

apply_branding() {
  local RES="$1"
  [[ -d "$RES" ]] || return 0

  # brand.ftl (Fluent — used by most modern UI strings)
  local BRAND_FTL_DEST="$RES/browser/localization/en-US/branding/brand.ftl"
  mkdir -p "$(dirname "$BRAND_FTL_DEST")"
  cp "$BRANDING/locales/en-US/brand.ftl" "$BRAND_FTL_DEST"

  # brand.properties (legacy strings — used by About dialog title)
  local BRAND_PROPS_DEST="$RES/browser/chrome/en-US/locale/branding/brand.properties"
  mkdir -p "$(dirname "$BRAND_PROPS_DEST")"
  cp "$BRANDING/locales/en-US/brand.properties" "$BRAND_PROPS_DEST"

  # about-logo.png + about-wordmark.svg (About dialog visuals)
  local LOGO_DIR="$RES/browser/chrome/browser/content/branding"
  if [[ -d "$LOGO_DIR" ]]; then
    cp "$BRANDING/content/about-logo.png"       "$LOGO_DIR/about-logo.png"
    cp "$BRANDING/content/about-logo@2x.png"    "$LOGO_DIR/about-logo@2x.png"     2>/dev/null || \
      cp "$BRANDING/content/about-logo.png"     "$LOGO_DIR/about-logo@2x.png"
    cp "$BRANDING/content/about-logo-private.png"    "$LOGO_DIR/about-logo-private.png"    2>/dev/null || true
    cp "$BRANDING/content/about-logo-private@2x.png" "$LOGO_DIR/about-logo-private@2x.png" 2>/dev/null || true
    cp "$BRANDING/content/about-wordmark.svg"   "$LOGO_DIR/about-wordmark.svg"     2>/dev/null || true
    cp "$BRANDING/content/firefox-wordmark.svg" "$LOGO_DIR/firefox-wordmark.svg"   2>/dev/null || true
    cp "$BRANDING/content/aboutDialog.css"      "$LOGO_DIR/aboutDialog.css"        2>/dev/null || true
  fi

  # aboutDialog.xhtml — patch URLs to tmrw.w3ai.io
  local ABOUT_XHTML="$RES/browser/chrome/browser/content/browser/aboutDialog.xhtml"
  if [[ -f "$ABOUT_XHTML" ]]; then
    sed -i '' 's|https://www\.plato\.ai/[^"]*|https://tmrw.w3ai.io|g' "$ABOUT_XHTML" 2>/dev/null || true
    sed -i '' 's|https://w3ai\.io/[^"]*|https://tmrw.w3ai.io|g'        "$ABOUT_XHTML" 2>/dev/null || true
    sed -i '' 's|href="https://tmrw\.w3ai\.io" data-l10n-name="helpus-getInvolvedLink"|href="https://tmrw.w3ai.io/releases" data-l10n-name="helpus-getInvolvedLink"|' "$ABOUT_XHTML" 2>/dev/null || true
  fi

  # Patch version display (artifact builds bake 151.0a1; show 1.0.0 instead)
  local APPC="$RES/modules/AppConstants.sys.mjs"
  if [[ -f "$APPC" ]]; then
    sed -i '' 's/MOZ_APP_VERSION: "151\.0a1"/MOZ_APP_VERSION: "1.0.0"/' "$APPC" 2>/dev/null || true
    sed -i '' 's/MOZ_APP_VERSION_DISPLAY: "151\.0a1"/MOZ_APP_VERSION_DISPLAY: "1.0.0"/' "$APPC" 2>/dev/null || true
  fi

  # Assets.car (macOS 11+ app icon — 348K TMRW version, not 740K+ Nightly)
  [[ -f "$BRANDING/Assets.car" ]] && cp "$BRANDING/Assets.car" "$RES/Assets.car"

  # firefox.icns / document.icns
  [[ -f "$BRANDING/firefox.icns"  ]] && cp "$BRANDING/firefox.icns"  "$RES/firefox.icns"
  [[ -f "$BRANDING/document.icns" ]] && cp "$BRANDING/document.icns" "$RES/document.icns"

  # Tab favicon icons (icon16.png / icon32.png → default16/32.png from branding)
  local FAVICON_DIR="$RES/browser/chrome/browser/content/branding"
  if [[ -d "$FAVICON_DIR" ]]; then
    [[ -f "$BRANDING/default16.png" ]] && cp "$BRANDING/default16.png" "$FAVICON_DIR/icon16.png"
    [[ -f "$BRANDING/default32.png" ]] && cp "$BRANDING/default32.png" "$FAVICON_DIR/icon32.png"
  fi

  # firefox-branding.js (processed — replaces symlink to unofficial/ which has Nightly prefs)
  local PREFS_FILE="$RES/browser/defaults/preferences/firefox-branding.js"
  if [[ -e "$PREFS_FILE" ]]; then
    rm -f "$PREFS_FILE"
    cat > "$PREFS_FILE" << 'PREFS'
/* TMRW W3 Browser branding prefs — generated by dev-build.sh */
pref("startup.homepage_override_url", "");
pref("startup.homepage_welcome_url", "about:newtab");
pref("startup.homepage_welcome_url.additional", "");
pref("app.update.interval", 21600);
pref("app.update.promptWaitTime", 691200);
pref("app.update.url.manual", "");
pref("app.update.url.details", "");
pref("app.releaseNotesURL", "");
pref("app.releaseNotesURL.aboutDialog", "");
pref("app.releaseNotesURL.prompt", "");
pref("app.update.checkInstallTime.days", 63);
pref("app.update.badgeWaitTime", 345600);
pref("devtools.selfxss.count", 0);
pref("identity.fxaccounts.enabled", false);
pref("identity.fxaccounts.toolbar.enabled", false);
pref("identity.fxaccounts.toolbar.defaultVisible", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.monitorEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.relayEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.vpnEnabled", false);
pref("identity.fxaccounts.remote.root", "");
pref("identity.fxaccounts.remote.profile.uri", "");
pref("identity.fxaccounts.remote.oauth.uri", "");
pref("identity.fxaccounts.remote.pairing.uri", "");
pref("identity.fxaccounts.autoconfig.uri", "");
pref("identity.sync.tokenserver.uri", "");
pref("identity.sendtabpromo.url", "");
pref("identity.mobilepromo.android", "");
pref("identity.mobilepromo.ios", "");
pref("identity.fxaccounts.telemetry.clientAssociationPing.enabled", false);
pref("browser.preferences.experimental.hidden", true);
pref("browser.preferences.moreFromMozilla", false);
pref("app.support.baseURL", "about:blank#");
pref("browser.aboutwelcome.enabled", false);
pref("browser.preonboarding.enabled", false);
pref("termsofuse.bypassNotification", true);
pref("messaging-system.askForFeedback", false);
pref("extensions.getAddons.discovery.api_url", "");
pref("extensions.htmlaboutaddons.recommendations.enabled", false);
pref("extensions.recommendations.hideNotice", true);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.server", "");
pref("toolkit.telemetry.archive.enabled", false);
pref("toolkit.telemetry.shutdownPingSender.enabled", false);
pref("toolkit.telemetry.firstShutdownPing.enabled", false);
pref("toolkit.telemetry.newProfilePing.enabled", false);
pref("toolkit.telemetry.updatePing.enabled", false);
pref("toolkit.telemetry.bhrPing.enabled", false);
pref("toolkit.telemetry.user_characteristics_ping.opt-out", true);
pref("toolkit.telemetry.dap_enabled", false);
pref("toolkit.telemetry.dap_task1_enabled", false);
pref("toolkit.telemetry.dap_visit_counting_enabled", false);
pref("app.normandy.enabled", false);
pref("app.normandy.api_url", "");
pref("app.shield.optoutstudies.enabled", false);
pref("nimbus.telemetry.targetingContextEnabled", false);
pref("browser.crashReports.unsubmittedCheck.enabled", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
pref("browser.tabs.crashReporting.sendReport", false);
pref("browser.urlbar.merino.endpointURL", "");
pref("browser.urlbar.merino.ohttpConfigURL", "");
pref("browser.urlbar.merino.ohttpRelayURL", "");
pref("browser.topsites.contile.endpoint", "");
pref("browser.partnerlink.attributionURL", "");
pref("toolkit.coverage.endpoint.base", "");
pref("app.feedback.baseURL", "");
pref("browser.search.serpEventTelemetryCategorization.enabled", false);
PREFS
  fi
}

# Replace unofficial/ icons so Nightly.app symlinks auto-pick up TMRW logos and tab favicon
UNOFFICIAL="$REPO_ROOT/browser/branding/unofficial"
for LOGO in about-logo.png about-logo@2x.png about-logo-private.png about-logo-private@2x.png about-wordmark.svg firefox-wordmark.svg; do
    SRC="$BRANDING/content/$LOGO"
    [[ -f "$SRC" ]] && cp "$SRC" "$UNOFFICIAL/content/$LOGO"
done
for SIZE in 16 22 24 32 48 64 128 256; do
    SRC="$BRANDING/default${SIZE}.png"
    [[ -f "$SRC" ]] && cp "$SRC" "$UNOFFICIAL/default${SIZE}.png"
done

# Apply to all dev app locations (mach run uses Nightly.app on macOS artifact builds)
apply_branding "$WORK_APP/Contents/Resources"
apply_branding "$OBJ_DIR/dist/Nightly.app/Contents/Resources"
apply_branding "$OBJ_DIR/dist/W3Ai.app/Contents/Resources"
apply_branding "$BIN_DIR"

# Fix CFBundleName and InfoPlist.strings for Nightly.app and W3Ai.app
for APP in "$OBJ_DIR/dist/Nightly.app" "$OBJ_DIR/dist/W3Ai.app"; do
    [[ -d "$APP" ]] || continue
    /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Browser" "$APP/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Browser" "$APP/Contents/Info.plist" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW Browser" "$APP/Contents/Info.plist" 2>/dev/null || true
    STRINGS="$APP/Contents/Resources/en.lproj/InfoPlist.strings"
    if [[ -f "$STRINGS" ]]; then
        plutil -convert xml1 "$STRINGS" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Set :CFBundleName TMRW Browser" "$STRINGS" 2>/dev/null || \
          /usr/libexec/PlistBuddy -c "Add :CFBundleName string TMRW Browser" "$STRINGS" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TMRW Browser" "$STRINGS" 2>/dev/null || \
          /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TMRW Browser" "$STRINGS" 2>/dev/null || true
        plutil -convert binary1 "$STRINGS" 2>/dev/null
    fi
done

# Overlay JS/CSS from dist/bin into dev-run.app
RES="$WORK_APP/Contents/Resources"
rsync -a --delete "$BIN_DIR/browser/" "$RES/browser/"
[[ -d "$BIN_DIR/modules" ]] && rsync -a "$BIN_DIR/modules/"  "$RES/modules/"
[[ -d "$BIN_DIR/moz-src" ]] && rsync -a "$BIN_DIR/moz-src/"  "$RES/moz-src/"

# Re-apply branding to dev-run.app (rsync above may have overwritten brand files)
apply_branding "$WORK_APP/Contents/Resources"

# Clear startupCache so new prefs and branding strings take effect immediately
rm -rf "$PROFILE_DIR/startupCache" 2>/dev/null || true

echo "    Done."

# ── Step 4: launch ─────────────────────────────────────────────────────────
if $RUN; then
  echo "==> Launching browser..."
  pkill -f "dev-run.app/Contents/MacOS/firefox" 2>/dev/null || true
  sleep 0.5
  mkdir -p "$PROFILE_DIR"
  "$WORK_APP/Contents/MacOS/firefox" --no-remote -profile "$PROFILE_DIR" \
    > /tmp/tmrw-devrun.log 2>&1 &
  echo "    PID: $! (log: /tmp/tmrw-devrun.log)"
fi
