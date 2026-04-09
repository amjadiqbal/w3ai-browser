#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-emulator.sh [options]

Start the Android emulator, install, and launch the W3Ai Android app.

Options:
  --avd <name>          Android Virtual Device name (default: Pixel_6a)
  --apk <path>          Path to the APK file to install (required unless --build)
  --build               Build the debug APK first using tools/release/android/build.sh
  --sdk-root <path>     Android SDK root (default: ANDROID_SDK_ROOT or ~/Library/Android/sdk)
  --no-launch           Install APK but do not launch the app
  --cold-boot           Force a cold boot of the emulator
  --help                Show this help message

Package:
  org.mozilla.fenix.debug  (debug) or org.mozilla.fenix (release)

Examples:
  # Build and run on default Pixel_6a emulator:
  ./tools/release/android/run-emulator.sh --build

  # Install a previously built APK on a specific AVD:
  ./tools/release/android/run-emulator.sh --avd MyAVD --apk /path/to/app.apk

  # Just start the emulator without installing anything:
  ./tools/release/android/run-emulator.sh --avd Pixel_6a

Requirements:
  - Android SDK installed with HAXM or Apple Hypervisor support
  - At least one Android Virtual Device (AVD) created via Android Studio or avdmanager
  - adb in PATH or accessible via SDK platform-tools
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
AVD_NAME="Pixel_6a"
APK_PATH=""
DO_BUILD=0
SDK_ROOT="${ANDROID_SDK_ROOT:-}"
NO_LAUNCH=0
COLD_BOOT=0

resolve_sdk_root() {
  if [[ -n "$SDK_ROOT" ]]; then
    export ANDROID_SDK_ROOT="$SDK_ROOT"
    return 0
  fi

  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    SDK_ROOT="$ANDROID_SDK_ROOT"
    return 0
  fi

  if [[ -d "$HOME/Library/Android/sdk" ]]; then
    SDK_ROOT="$HOME/Library/Android/sdk"
    export ANDROID_SDK_ROOT="$SDK_ROOT"
    return 0
  fi

  echo "[✗] Error: Android SDK not found." >&2
  echo "    Set ANDROID_SDK_ROOT or pass --sdk-root <path>." >&2
  exit 1
}

find_adb() {
  if command -v adb >/dev/null 2>&1; then
    ADB="$(command -v adb)"
    return 0
  fi

  local candidate="$SDK_ROOT/platform-tools/adb"
  if [[ -x "$candidate" ]]; then
    ADB="$candidate"
    return 0
  fi

  echo "[✗] Error: adb not found in PATH or $SDK_ROOT/platform-tools/" >&2
  exit 1
}

find_emulator() {
  if command -v emulator >/dev/null 2>&1; then
    EMULATOR="$(command -v emulator)"
    return 0
  fi

  local candidate="$SDK_ROOT/emulator/emulator"
  if [[ -x "$candidate" ]]; then
    EMULATOR="$candidate"
    return 0
  fi

  echo "[✗] Error: emulator not found in PATH or $SDK_ROOT/emulator/" >&2
  exit 1
}

is_emulator_running() {
  "$ADB" devices 2>/dev/null | grep -q "emulator-"
}

wait_for_emulator_boot() {
  local max_wait=120
  local elapsed=0
  local interval=5

  echo "    Waiting for emulator to boot (up to ${max_wait}s)..."
  while [[ $elapsed -lt $max_wait ]]; do
    local boot_complete
    boot_complete="$("$ADB" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$boot_complete" == "1" ]]; then
      echo "    Emulator booted successfully."
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    echo "    Still waiting... (${elapsed}s)"
  done

  echo "[✗] Error: Emulator did not finish booting within ${max_wait}s." >&2
  exit 1
}

detect_app_id() {
  local apk="$1"
  if command -v aapt >/dev/null 2>&1; then
    aapt dump badging "$apk" 2>/dev/null | grep "package: name=" | sed "s/.*name='\([^']*\)'.*/\1/"
  else
    echo ""
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --avd)
      AVD_NAME="${2:-}"
      shift 2
      ;;
    --apk)
      APK_PATH="${2:-}"
      shift 2
      ;;
    --build)
      DO_BUILD=1
      shift
      ;;
    --sdk-root)
      SDK_ROOT="${2:-}"
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --cold-boot)
      COLD_BOOT=1
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
resolve_sdk_root
find_adb
find_emulator

echo "=========================================="
echo "W3Ai Android Emulator Runner"
echo "=========================================="
echo ""
echo "AVD:         $AVD_NAME"
echo "SDK root:    $SDK_ROOT"
echo ""

ADB="$ADB"

if [[ $DO_BUILD -eq 1 ]]; then
  echo "[1/4] Building debug APK"
  bash "$ROOT_DIR/tools/release/android/build.sh" --dev --sdk-root "$SDK_ROOT"
  APK_PATH="$(find "$ROOT_DIR" -path "*/gradle/build/mobile/android/fenix/app/outputs/apk/debug/*.apk" -type f 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -z "$APK_PATH" ]]; then
    APK_PATH="$(find "$ROOT_DIR/mobile/android/fenix/app/build/outputs/apk/debug" -name "*.apk" -type f 2>/dev/null | sort | tail -n 1 || true)"
  fi
  if [[ -z "$APK_PATH" || ! -f "$APK_PATH" ]]; then
    echo "[✗] Error: No APK found after build." >&2
    exit 1
  fi
  echo "[✓] APK built: $APK_PATH"
  echo ""
fi

if [[ -n "$APK_PATH" && ! -f "$APK_PATH" ]]; then
  echo "[✗] Error: APK not found: $APK_PATH" >&2
  exit 1
fi

STEP_LABEL="1/2"
if [[ $DO_BUILD -eq 1 && -n "$APK_PATH" ]]; then
  STEP_LABEL="2/4"
elif [[ $DO_BUILD -eq 1 ]]; then
  STEP_LABEL="2/3"
elif [[ -n "$APK_PATH" ]]; then
  STEP_LABEL="1/3"
fi

echo "[$STEP_LABEL] Starting emulator: $AVD_NAME"

if is_emulator_running; then
  echo "    Emulator already running."
else
  EMULATOR_ARGS=(-avd "$AVD_NAME" -no-audio -no-snapshot-save)
  if [[ $COLD_BOOT -eq 1 ]]; then
    EMULATOR_ARGS+=(-no-snapshot-load)
  fi
  "$EMULATOR" "${EMULATOR_ARGS[@]}" &>/dev/null &
  echo "    Emulator launched in background (PID: $!)."
  wait_for_emulator_boot
fi
echo "[✓] Emulator is running."
echo ""

if [[ -n "$APK_PATH" ]]; then
  echo "Installing APK on emulator"
  "$ADB" -e install -r "$APK_PATH"
  echo "[✓] APK installed."
  echo ""

  if [[ $NO_LAUNCH -eq 0 ]]; then
    APP_ID="$(detect_app_id "$APK_PATH")"
    if [[ -z "$APP_ID" ]]; then
      APP_ID="org.mozilla.fenix.debug"
      echo "    Could not detect app ID from APK, defaulting to $APP_ID"
    fi

    echo "Launching app: $APP_ID"
    "$ADB" -e shell am start -n "${APP_ID}/${APP_ID}.App" 2>/dev/null || \
      "$ADB" -e shell am start -n "${APP_ID}/.HomeActivity" 2>/dev/null || \
      "$ADB" -e shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1
    echo "[✓] App launched."
    echo ""
  fi
fi

echo "=========================================="
echo "✓ Emulator session active"
echo "=========================================="
echo ""
echo "ADB commands:"
echo "  adb -e devices          — list running emulators"
echo "  adb -e shell            — open a shell in the emulator"
echo "  adb -e logcat           — view device logs"
echo "  adb -e install -r <apk> — install a new APK"
echo ""
echo "To stop the emulator:"
echo "  adb -e emu kill"
echo ""
