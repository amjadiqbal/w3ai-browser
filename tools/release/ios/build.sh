#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build.sh [options]

Build W3Ai for iOS.

Options:
  --app-id <id>         Bundle identifier (default: org.w3ai.browser)
  --team-id <id>        Apple Developer Team ID (for signing)
  --provisioning <path> Provisioning profile path
  --dev                 Development build (for testing)
  --prod                Production build (for App Store)
  --objdir <path>       Optional object directory for output
  --help                Show this help message

Output:
  - iOS app package (.ipa)
  - Located in obj-ios*/dist/ or build artifacts directory
  - Ready for device installation or App Store submission

Requirements:
  - macOS with Xcode tools installed
  - iOS SDK (part of Xcode)
  - Apple Developer account (for signing/deployment)
  - Build environment set up via ./mach bootstrap
  - provisioning profiles configured for development or production

Notes:
  - Development builds can be installed on physical devices for testing
  - Production builds are optimized for App Store distribution
  - Notarization is not required for iOS; use App Store submission instead
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUNDLE_ID="org.w3ai.browser"
TEAM_ID=""
PROVISIONING_PROFILE=""
BUILD_TYPE="debug"
OBJ_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --provisioning)
      PROVISIONING_PROFILE="${2:-}"
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

echo "=========================================="
echo "W3Ai iOS Build"
echo "=========================================="
echo ""
echo "Build type:  $BUILD_TYPE"
echo "Bundle ID:   $BUNDLE_ID"
if [[ -n "$TEAM_ID" ]]; then
  echo "Team ID:     $TEAM_ID"
fi
echo ""

# Verify iOS configuration
if [[ ! -f "mobile/ios/moz.configure" ]]; then
  echo "[✗] Error: iOS configuration not found" >&2
  exit 1
fi

echo "[1/2] Building iOS application"
if [[ "$BUILD_TYPE" == "debug" ]]; then
  ./mach build --verbose
else
  ./mach build --verbose
fi
echo "[✓] Build complete"
echo ""

echo "[2/2] Packaging IPA"
./mach package
echo "[✓] Package complete"
echo ""

# Find the generated IPA
if [[ -z "$OBJ_DIR" ]]; then
  IPA_PATH="$(find obj-ios* -name "*.ipa" -type f 2>/dev/null | head -n 1 || true)"
else
  IPA_PATH="$(find "$OBJ_DIR" -name "*.ipa" -type f 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "$IPA_PATH" && -f "$IPA_PATH" ]]; then
  echo "=========================================="
  echo "✓ iOS build complete"
  echo "=========================================="
  echo ""
  echo "IPA ready: $IPA_PATH"
  ls -lh "$IPA_PATH"
  echo ""
  echo "Installation on device:"
  echo "  1. Open Xcode's Devices and Simulators window"
  echo "  2. Select your device"
  echo "  3. Drag the .ipa onto the device window"
  echo ""
  echo "Or use ios-deploy:"
  echo "  ios-deploy -b '$IPA_PATH'"
  echo ""
  echo "For App Store submission:"
  echo "  - Use Xcode to upload $IPA_PATH"
  echo "  - Or use xcrun altool to submit via command line"
  echo ""
else
  echo "[!] Warning: IPA not found in expected locations" >&2
  echo "    Check build output above for errors" >&2
fi

echo ""
