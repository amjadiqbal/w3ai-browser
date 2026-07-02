#!/usr/bin/env bash
# build-pkg.sh — wrap the notarized TMRW.app in a macOS .pkg installer
#
# Prerequisites:
#   1. A notarized DMG at dist/TMRW.dmg  (run scripts/notarize.sh first)
#   2. "Developer ID Installer" certificate in Keychain  (APPLE_INSTALLER_IDENTITY in .env)
#   3. APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID for PKG notarization
#
# Usage:
#   ./scripts/build-pkg.sh [/path/to/TMRW.dmg]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/ui.sh"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"

# ── Args ───────────────────────────────────────────────────────────────────────
INPUT_DMG="${1:-$OBJ_DIR/dist/TMRW.dmg}"
if [[ ! -f "$INPUT_DMG" ]]; then
  ui_fail "DMG not found: $INPUT_DMG"
  ui_info "Run ./scripts/notarize.sh first, or pass the DMG path as an argument."
  exit 1
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  ui_fail ".env not found. Copy .env.example to .env and fill in values."
  exit 1
fi
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}"; val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

# ── Config ────────────────────────────────────────────────────────────────────
VERSION="${APP_VERSION:-$(grep 'MOZ_APP_VERSION=' "$REPO_ROOT/browser/branding/w3ai/configure.sh" | head -1 | cut -d= -f2 | tr -d '"')}"
BUNDLE_ID="${APPLE_BUNDLE_ID:-org.w3ai.browser}"
INSTALLER_IDENTITY="${APPLE_INSTALLER_IDENTITY:-}"
OUT_PKG="$OBJ_DIR/dist/TMRW-v${VERSION}.pkg"

WORK_DIR="$(mktemp -d /tmp/tmrw-pkg.XXXXXX)"
MOUNT_POINT="$(mktemp -d /tmp/tmrw-pkg-mount.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rm -rf "$WORK_DIR" "$MOUNT_POINT"
}
trap cleanup EXIT

ui_banner "TMRW v${VERSION} — build PKG installer"

# ── [1/5] Extract app from DMG ────────────────────────────────────────────────
ui_step 1 5 "Extracting app from DMG"
hdiutil attach "$INPUT_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
APP_SRC="$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)"
if [[ -z "$APP_SRC" ]]; then
  ui_fail "No .app found inside $INPUT_DMG"
  exit 1
fi
cp -a "$APP_SRC" "$WORK_DIR/TMRW.app"
hdiutil detach "$MOUNT_POINT" -quiet
ui_ok "Extracted $(basename "$APP_SRC")"

# ── [2/5] Build component package ────────────────────────────────────────────
ui_step 2 5 "Building component package"
COMPONENT_PKG="$WORK_DIR/TMRW-component.pkg"
PKG_ARGS=(
  --component "$WORK_DIR/TMRW.app"
  --install-location /Applications
  --identifier "$BUNDLE_ID"
  --version "$VERSION"
)
[[ -n "$INSTALLER_IDENTITY" ]] && PKG_ARGS+=(--sign "$INSTALLER_IDENTITY")
pkgbuild "${PKG_ARGS[@]}" "$COMPONENT_PKG"
ui_ok "Component package ready"

# ── [3/5] Build distribution package ─────────────────────────────────────────
ui_step 3 5 "Building distribution package"
DIST_XML="$WORK_DIR/distribution.xml"
cat > "$DIST_XML" <<DISTEOF
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<installer-gui-script minSpecVersion="2">
    <title>TMRW</title>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="10.15"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="${BUNDLE_ID}"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="${BUNDLE_ID}" visible="false">
        <pkg-ref id="${BUNDLE_ID}"/>
    </choice>
    <pkg-ref id="${BUNDLE_ID}" version="${VERSION}" onConclusion="none">TMRW-component.pkg</pkg-ref>
</installer-gui-script>
DISTEOF

PROD_ARGS=(
  --distribution "$DIST_XML"
  --package-path "$WORK_DIR"
)
[[ -n "$INSTALLER_IDENTITY" ]] && PROD_ARGS+=(--sign "$INSTALLER_IDENTITY")
productbuild "${PROD_ARGS[@]}" "$OUT_PKG"
ui_ok "Distribution package: $(basename "$OUT_PKG")"

# ── [4/5] Notarize PKG ───────────────────────────────────────────────────────
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  ui_step 4 5 "Submitting to Apple Notary Service (1–5 min)"
  ui_spinner_start "Notarizing PKG…"
  xcrun notarytool submit "$OUT_PKG" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait 2>&1 | grep -E "status:|id:" | head -5 || true
  ui_spinner_stop ok
  ui_ok "Notarization accepted"

  # ── [5/5] Staple ─────────────────────────────────────────────────────────
  ui_step 5 5 "Stapling notarization ticket"
  xcrun stapler staple "$OUT_PKG"
  ui_ok "Stapled"
else
  ui_warn "Skipping notarization — set APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID in .env"
  ui_step 5 5 "Done (unsigned)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
PKG_SIZE="$(du -sh "$OUT_PKG" | cut -f1)"
echo ""
ui_ok "${PKG_SIZE} — $OUT_PKG"
echo ""
printf "  Install:   double-click %s\n" "$(basename "$OUT_PKG")"
printf "  Or:        sudo installer -pkg \"%s\" -target /\n" "$OUT_PKG"
echo ""
