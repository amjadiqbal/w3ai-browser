#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-simulator.sh [options]

Build, install, and launch GeckoTestBrowser on an iOS Simulator.

Options:
  --build                       Build simulator app before install (default: on)
  --no-build                    Skip build and use an existing .app
  --app-path <path>             Path to an existing .app bundle
  --device-name <name>          Simulator device name (default: W3Ai-iPhone)
  --device-type <id>            Simulator device type id (default: com.apple.CoreSimulator.SimDeviceType.iPhone-17)
  --runtime-id <id>             Simulator runtime id (auto-detected if omitted)
  --scheme <name>               Xcode scheme (default: GeckoTestBrowser)
  --configuration <name>        Xcode configuration (default: Debug)
  --bundle-id <id>              App bundle identifier (default: org.mozilla.ios.GeckoTestBrowser)
  --derived-data-path <path>    DerivedData output (default: mobile/ios/build/derived-data-simulator)
  --project <path>              Xcode project path
  --no-launch                   Install app but do not launch it
  --help                        Show this help message

Examples:
  ./tools/release/ios/run-simulator.sh
  ./tools/release/ios/run-simulator.sh --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-16
  ./tools/release/ios/run-simulator.sh --runtime-id com.apple.CoreSimulator.SimRuntime.iOS-18-5

Requirements:
  - macOS with Xcode installed
  - iOS Simulator runtime installed (Xcode -> Settings -> Platforms)
  - xcodebuild and xcrun available
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/mobile/ios/GeckoTestBrowser/GeckoTestBrowser.xcodeproj"
SCHEME="GeckoTestBrowser"
CONFIGURATION="Debug"
BUNDLE_ID="org.mozilla.ios.GeckoTestBrowser"
DEVICE_NAME="W3Ai-iPhone"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
RUNTIME_ID=""
DERIVED_DATA_PATH="$ROOT_DIR/mobile/ios/build/derived-data-simulator"
APP_PATH=""
DO_BUILD=1
NO_LAUNCH=0

require_tools() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "[✗] Error: xcodebuild not found." >&2
    exit 1
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "[✗] Error: xcrun not found." >&2
    exit 1
  fi
}

latest_runtime_id() {
  xcrun simctl list runtimes 2>/dev/null \
    | grep "com.apple.CoreSimulator.SimRuntime.iOS" \
    | grep -v unavailable \
    | sed -E 's/.*- (com\.apple\.CoreSimulator\.SimRuntime\.iOS[^ ]*).*/\1/' \
    | tail -n 1
}

find_or_create_device_udid() {
  local name="$1"
  local dtype="$2"
  local rid="$3"

  local udid
  udid="$(xcrun simctl list devices 2>/dev/null | sed -n "s/^ *${name} (\([A-F0-9-]*\)) .*/\1/p" | tr -d '()' | head -n 1 || true)"
  if [[ -n "$udid" ]]; then
    echo "$udid"
    return 0
  fi

  xcrun simctl create "$name" "$dtype" "$rid"
}

boot_device() {
  local udid="$1"
  local state

  state="$(xcrun simctl list devices 2>/dev/null | grep "$udid" | sed -E 's/.*\((Booted|Shutdown)\).*/\1/' | head -n 1 || true)"
  if [[ "$state" != "Booted" ]]; then
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  fi

  xcrun simctl bootstatus "$udid" -b
}

build_simulator_app() {
  mkdir -p "$DERIVED_DATA_PATH"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "[✗] Error: built app not found at $APP_PATH" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      DO_BUILD=1
      shift
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --device-name)
      DEVICE_NAME="${2:-}"
      shift 2
      ;;
    --device-type)
      DEVICE_TYPE="${2:-}"
      shift 2
      ;;
    --runtime-id)
      RUNTIME_ID="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
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
require_tools

if [[ $DO_BUILD -eq 1 ]]; then
  echo "[1/4] Building simulator app"
  build_simulator_app
  echo "[✓] Built app: $APP_PATH"
  echo ""
else
  if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "[✗] Error: --no-build requires --app-path <path-to-app>." >&2
    exit 1
  fi
fi

if [[ -z "$RUNTIME_ID" ]]; then
  RUNTIME_ID="$(latest_runtime_id || true)"
fi

if [[ -z "$RUNTIME_ID" ]]; then
  echo "[✗] Error: no iOS simulator runtime found." >&2
  echo "    Install one in Xcode -> Settings -> Platforms, then run again." >&2
  echo "    You can verify with: xcrun simctl list runtimes" >&2
  exit 1
fi

echo "[2/4] Creating or selecting simulator"
UDID="$(find_or_create_device_udid "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
echo "[✓] Simulator UDID: $UDID"
echo ""

echo "[3/4] Booting simulator"
boot_device "$UDID"
open -a Simulator >/dev/null 2>&1 || true
echo "[✓] Simulator booted"
echo ""

echo "[4/4] Installing app"
xcrun simctl install "$UDID" "$APP_PATH"
echo "[✓] App installed"
echo ""

if [[ $NO_LAUNCH -eq 0 ]]; then
  echo "Launching: $BUNDLE_ID"
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
  echo "[✓] App launched"
  echo ""
fi

echo "=========================================="
echo "✓ iOS simulator run complete"
echo "=========================================="
echo ""
echo "App path:  $APP_PATH"
echo "Bundle ID: $BUNDLE_ID"
echo "Device:    $DEVICE_NAME ($UDID)"
echo "Runtime:   $RUNTIME_ID"
echo ""
echo "Useful commands:"
echo "  xcrun simctl list devices"
echo "  xcrun simctl uninstall $UDID $BUNDLE_ID"
echo "  xcrun simctl shutdown $UDID"
echo ""
