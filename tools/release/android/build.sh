#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build.sh [options]

Build W3Ai for Android as APK.

Options:
  --app-id <id>         Android app ID (default: org.w3ai.browser)
  --version <version>   Version code (sets app version)
  --dev                 Development build (faster, includes debug symbols)
  --prod                Production build (optimized, smaller)
  --release-mode        Release mode build (code signing ready)
  --objdir <path>       Optional object directory for output
  --help                Show this help message

Output:
  - Android application package (.apk or .aab)
  - Located in obj-android*/dist/

Requirements:
  - Android NDK and SDK configured
  - Java Development Kit (JDK) installed
  - Android build environment set up via ./mach bootstrap
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
APP_ID="org.w3ai.browser"
VERSION_CODE=""
BUILD_TYPE="debug"
OBJ_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --version)
      VERSION_CODE="${2:-}"
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
    --release-mode)
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
echo "W3Ai Android Build"
echo "=========================================="
echo ""
echo "Build type:  $BUILD_TYPE"
echo "App ID:      $APP_ID"
if [[ -n "$VERSION_CODE" ]]; then
  echo "Version:     $VERSION_CODE"
fi
echo ""

# Verify Android configuration
if [[ ! -f "mobile/android/moz.configure" ]]; then
  echo "[✗] Error: Android configuration not found" >&2
  exit 1
fi

echo "[1/2] Building Android application"
if [[ "$BUILD_TYPE" == "debug" ]]; then
  ./mach build --verbose
else
  ./mach build --verbose
fi
echo "[✓] Build complete"
echo ""

echo "[2/2] Packaging APK"
./mach package
echo "[✓] Package complete"
echo ""

# Find the generated APK
if [[ -z "$OBJ_DIR" ]]; then
  APK_PATH="$(find obj-android* -name "*.apk" -type f 2>/dev/null | head -n 1 || true)"
else
  APK_PATH="$(find "$OBJ_DIR" -name "*.apk" -type f 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "$APK_PATH" && -f "$APK_PATH" ]]; then
  echo "=========================================="
  echo "✓ Android build complete"
  echo "=========================================="
  echo ""
  echo "APK ready: $APK_PATH"
  ls -lh "$APK_PATH"
  echo ""
  echo "Installation on device:"
  echo "  adb install -r '$APK_PATH'"
  echo ""
else
  echo "[!] Warning: APK not found in expected locations" >&2
  echo "    Check build output above for errors" >&2
fi

echo ""
