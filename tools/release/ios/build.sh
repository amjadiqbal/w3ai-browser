#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build.sh [options]

Build the iOS prototype app from mobile/ios/GeckoTestBrowser.

Options:
  --dev                           Build/export a development IPA
  --prod                          Build/export a production IPA
  --team-id <id>                  Apple Developer Team ID for signing
  --bundle-id <id>                Bundle identifier override
  --scheme <name>                 Xcode scheme (default: GeckoTestBrowser)
  --export-method <method>        development, ad-hoc, app-store (default: development for --dev, app-store for --prod)
  --archive-path <path>           Destination .xcarchive path
  --export-path <path>            Destination folder for exported IPA
  --objdir <path>                 Object directory for the temporary iOS MOZCONFIG
  --mozconfig <path>              Existing iOS MOZCONFIG to use instead of generating one
  --help                          Show this help message

Output:
  - .xcarchive under mobile/ios/build/
  - .ipa under the export path

Requirements:
  - macOS with Xcode installed
  - iOS build environment bootstrapped via ./mach bootstrap
  - Valid Apple signing setup in Xcode for device IPA export

Notes:
  - iOS distribution uses IPA export, not DMG and not notarization
  - This script archives and exports GeckoTestBrowser via xcodebuild
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUNDLE_ID="org.mozilla.ios.GeckoTestBrowser"
TEAM_ID=""
BUILD_TYPE="debug"
OBJ_DIR=""
CUSTOM_MOZCONFIG=""
SCHEME="GeckoTestBrowser"
EXPORT_METHOD=""
ARCHIVE_PATH=""
EXPORT_PATH=""
PROJECT_PATH="$ROOT_DIR/mobile/ios/GeckoTestBrowser/GeckoTestBrowser.xcodeproj"

cleanup() {
  if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

create_ios_mozconfig() {
  local mozconfig_path="$1"
  local resolved_objdir="$2"

  cat > "$mozconfig_path" <<EOF
ac_add_options --enable-application=mobile/ios
mk_add_options MOZ_OBJDIR=$resolved_objdir
EOF
}

create_export_options_plist() {
  local plist_path="$1"

  cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
EOF

  if [[ -n "$TEAM_ID" ]]; then
    cat >> "$plist_path" <<EOF
  <key>teamID</key>
  <string>$TEAM_ID</string>
EOF
  fi

  cat >> "$plist_path" <<'EOF'
</dict>
</plist>
EOF
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --export-method)
      EXPORT_METHOD="${2:-}"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --export-path)
      EXPORT_PATH="${2:-}"
      shift 2
      ;;
    --mozconfig)
      CUSTOM_MOZCONFIG="${2:-}"
      shift 2
      ;;
    --dev)
      BUILD_TYPE="debug"
      shift
      ;;
    --prod)
      BUILD_TYPE="release"
      shift
      ;;
    --objdir)
      OBJ_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[✗] Error: xcodebuild not found" >&2
  exit 1
fi

if [[ -z "$OBJ_DIR" ]]; then
  OBJ_DIR="$ROOT_DIR/obj-w3ai-ios"
fi

if [[ -n "$CUSTOM_MOZCONFIG" ]]; then
  MOZCONFIG_PATH="$CUSTOM_MOZCONFIG"
else
  TEMP_DIR="$(mktemp -d)"
  MOZCONFIG_PATH="$TEMP_DIR/ios.mozconfig"
  create_ios_mozconfig "$MOZCONFIG_PATH" "$OBJ_DIR"
fi

if [[ -z "$EXPORT_METHOD" ]]; then
  if [[ "$BUILD_TYPE" == "debug" ]]; then
    EXPORT_METHOD="development"
  else
    EXPORT_METHOD="app-store"
  fi
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$ROOT_DIR/mobile/ios/build/$SCHEME-${BUILD_TYPE}.xcarchive"
fi

if [[ -z "$EXPORT_PATH" ]]; then
  EXPORT_PATH="$ROOT_DIR/mobile/ios/build/export-$SCHEME-${BUILD_TYPE}"
fi

TEMP_DIR="${TEMP_DIR:-$(mktemp -d)}"
EXPORT_OPTIONS_PLIST="$TEMP_DIR/export-options.plist"
create_export_options_plist "$EXPORT_OPTIONS_PLIST"

CONFIGURATION="Debug"
if [[ "$BUILD_TYPE" == "release" ]]; then
  CONFIGURATION="Release"
fi

echo "=========================================="
echo "W3Ai iOS Build"
echo "=========================================="
echo ""
echo "Build type:  $BUILD_TYPE"
echo "Bundle ID:   $BUNDLE_ID"
echo "Scheme:      $SCHEME"
echo "Archive:     $ARCHIVE_PATH"
echo "Export dir:  $EXPORT_PATH"
echo "Method:      $EXPORT_METHOD"
echo "MOZCONFIG:   $MOZCONFIG_PATH"
if [[ -n "$TEAM_ID" ]]; then
  echo "Team ID:     $TEAM_ID"
fi
echo ""

echo "[1/3] Building Gecko for iOS"
MOZCONFIG="$MOZCONFIG_PATH" ./mach build --verbose
echo "[✓] Build complete"
echo ""

echo "[2/3] Archiving iOS application"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  -destination "generic/platform=iOS"
  -allowProvisioningUpdates
  archive
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
  CODE_SIGN_STYLE=Automatic
)

if [[ -n "$TEAM_ID" ]]; then
  XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"
echo "[✓] Archive complete"
echo ""

echo "[3/3] Exporting IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates
echo "[✓] IPA export complete"

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -type f | head -n 1 || true)"

if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "[✗] Error: IPA not found under $EXPORT_PATH" >&2
  exit 1
fi

echo ""
echo "=========================================="
echo "✓ iOS build complete"
echo "=========================================="
echo ""
echo "Archive ready: $ARCHIVE_PATH"
echo "IPA ready:     $IPA_PATH"
ls -lh "$IPA_PATH"
echo ""
echo "Install on a device with Xcode Devices and Simulators or ios-deploy:"
echo "  ios-deploy -b '$IPA_PATH'"
echo ""
echo "For App Store submission, upload the exported IPA via Xcode Organizer or Transporter."
echo ""
