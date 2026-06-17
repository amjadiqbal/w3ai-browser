#!/usr/bin/env bash
# publish-update.sh — publish a new TMRW W3 Browser release to the update server
#
# What this does:
#   1. Reads the current version from browser/config/version.txt
#   2. Notarizes the DMG (calls notarize.sh)
#   3. Uploads the DMG + MAR file to S3 (or any static host)
#   4. Writes a fresh update.xml and uploads it
#   5. Users with the browser installed get a silent update prompt
#
# Prerequisites:
#   - AWS CLI installed + configured (brew install awscli && aws configure)
#   - .env file with S3_BUCKET set
#   - Run ./mach build && ./mach package first

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ_DIR="$REPO_ROOT/obj-x86_64-apple-darwin25.5.0"
VERSION="$(cat "$REPO_ROOT/browser/config/version.txt" | tr -d '[:space:]')"
APP_NAME="TMRW W3 Browser"

# ── Load .env ──────────────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env"
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    val="${val#\"}" ; val="${val%\"}"
    val="${val#\'}" ; val="${val%\'}"
    export "$key=$val"
  fi
done < "$ENV_FILE"

S3_BUCKET="${S3_BUCKET:-tmrw-w3-browser-updates}"
CDN_BASE="${CDN_BASE:-https://updates.tmrw.w3ai.io}"

echo "==> Publishing TMRW W3 Browser v$VERSION"
echo ""

# ── Step 1: Notarize + produce signed DMG ────────────────────────────────────
echo "==> [1/4] Notarizing..."
"$REPO_ROOT/scripts/notarize.sh"

SIGNED_DMG="$OBJ_DIR/dist/$APP_NAME.dmg"

# ── Step 2: Locate the MAR update file ───────────────────────────────────────
echo ""
echo "==> [2/4] Locating MAR update package..."
MAR_FILE="$(ls "$OBJ_DIR/dist/"*.complete.mar 2>/dev/null | head -1)"
if [[ -z "$MAR_FILE" ]]; then
  echo "    No .mar file found — building update package..."
  ./mach package-multi-locale 2>/dev/null || true
  MAR_FILE="$(ls "$OBJ_DIR/dist/"*.complete.mar 2>/dev/null | head -1)"
fi

if [[ -z "$MAR_FILE" ]]; then
  echo "    WARNING: No MAR file found. Uploading DMG only (no silent update)."
  MAR_SIZE=0
  MAR_HASH=""
else
  MAR_SIZE="$(stat -f%z "$MAR_FILE")"
  MAR_HASH="$(shasum -a 512 "$MAR_FILE" | awk '{print $1}')"
  echo "    MAR: $MAR_FILE ($MAR_SIZE bytes)"
fi

# ── Step 3: Upload to S3 ──────────────────────────────────────────────────────
echo ""
echo "==> [3/4] Uploading to S3 bucket: $S3_BUCKET..."

DMG_KEY="releases/v$VERSION/$APP_NAME-$VERSION.dmg"
aws s3 cp "$SIGNED_DMG" "s3://$S3_BUCKET/$DMG_KEY" \
  --content-type "application/x-apple-diskimage" \
  --acl public-read

if [[ -n "$MAR_FILE" ]]; then
  MAR_KEY="releases/v$VERSION/$(basename "$MAR_FILE")"
  aws s3 cp "$MAR_FILE" "s3://$S3_BUCKET/$MAR_KEY" \
    --content-type "application/octet-stream" \
    --acl public-read
  MAR_URL="$CDN_BASE/$MAR_KEY"
fi

DMG_URL="$CDN_BASE/$DMG_KEY"
echo "    DMG uploaded: $DMG_URL"

# ── Step 4: Generate and upload update.xml ───────────────────────────────────
echo ""
echo "==> [4/4] Writing update.xml..."

BUILD_ID="$(date +%Y%m%d%H%M%S)"

if [[ -n "$MAR_FILE" ]]; then
UPDATE_XML="<?xml version=\"1.0\"?>
<updates>
  <update type=\"minor\"
          displayVersion=\"$VERSION\"
          appVersion=\"$VERSION\"
          platformVersion=\"$VERSION\"
          buildID=\"$BUILD_ID\">
    <patch type=\"complete\"
           URL=\"$MAR_URL\"
           size=\"$MAR_SIZE\"
           hashFunction=\"SHA512\"
           hashValue=\"$MAR_HASH\"/>
  </update>
</updates>"
else
UPDATE_XML="<?xml version=\"1.0\"?>
<updates/>"
fi

echo "$UPDATE_XML" > /tmp/update.xml

# Upload update.xml to all path prefixes the browser might request
# The browser substitutes %PRODUCT%, %VERSION% etc — we serve the same XML
# for all combinations by using a wildcard-friendly path structure.
aws s3 cp /tmp/update.xml "s3://$S3_BUCKET/update/1/TMRW W3 Browser/$VERSION/" \
  --recursive --exclude "*" --include "*.xml" 2>/dev/null || \
aws s3 cp /tmp/update.xml "s3://$S3_BUCKET/update.xml" \
  --content-type "text/xml" \
  --acl public-read

echo ""
echo "============================================================"
echo "  Published v$VERSION"
echo "  DMG download: $DMG_URL"
echo ""
echo "  Users with TMRW W3 Browser installed will be prompted"
echo "  to update within 6 hours (next background check)."
echo "============================================================"
