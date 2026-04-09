#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build.sh [options]

Build the Android app from mobile/android/fenix.

Options:
  --dev                         Build the debug APK
  --prod                        Build the release APK
  --target <triple>             Android target triple (default: aarch64-linux-android)
  --sdk-root <path>             Android SDK root (default: ANDROID_SDK_ROOT or ~/Library/Android/sdk)
  --objdir <path>               Object directory for the temporary Android MOZCONFIG
  --mozconfig <path>            Existing Android MOZCONFIG to use instead of generating one
  --keystore <path>             Sign the release APK with this keystore
  --key-alias <name>            Keystore alias used for signing
  --store-password-env <name>   Environment variable containing the keystore password
  --key-password-env <name>     Environment variable containing the key password
  --help                        Show this help message

Output:
  - Debug APK: mobile/android/fenix/app/build/outputs/apk/debug/
  - Release APK: mobile/android/fenix/app/build/outputs/apk/release/
  - Signed release APK: same directory with -signed suffix

Requirements:
  - Android SDK installed
  - Java Development Kit installed
  - Android build environment bootstrapped via ./mach bootstrap
  - For signed release builds: zipalign + apksigner from Android build-tools
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_TYPE="debug"
TARGET_TRIPLE="aarch64-linux-android"
SDK_ROOT="${ANDROID_SDK_ROOT:-}"
OBJ_DIR=""
CUSTOM_MOZCONFIG=""
KEYSTORE=""
KEY_ALIAS=""
STORE_PASSWORD_ENV=""
KEY_PASSWORD_ENV=""

cleanup() {
  if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

resolve_java_home() {
  if [[ -n "${JAVA_HOME:-}" ]]; then
    return 0
  fi

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    JAVA_HOME="$(/usr/libexec/java_home)"
    export JAVA_HOME
  fi
}

resolve_sdk_root() {
  if [[ -n "$SDK_ROOT" ]]; then
    export ANDROID_SDK_ROOT="$SDK_ROOT"
    return 0
  fi

  if [[ -d "$HOME/Library/Android/sdk" ]]; then
    SDK_ROOT="$HOME/Library/Android/sdk"
    export ANDROID_SDK_ROOT="$SDK_ROOT"
    return 0
  fi

  echo "[✗] Error: Android SDK not found" >&2
  echo "    Set ANDROID_SDK_ROOT or pass --sdk-root <path>." >&2
  exit 1
}

find_sdk_tool() {
  local tool_name="$1"
  find "$SDK_ROOT/build-tools" -name "$tool_name" -type f 2>/dev/null | sort -V | tail -n 1 || true
}

create_android_mozconfig() {
  local mozconfig_path="$1"
  local resolved_objdir="$2"

  cat > "$mozconfig_path" <<EOF
ac_add_options --enable-application=mobile/android
ac_add_options --enable-artifact-builds
ac_add_options --target=$TARGET_TRIPLE
mk_add_options MOZ_OBJDIR=$resolved_objdir
EOF
}

prepare_gradle_intermediates() {
  local variant_suffix="Debug"
  if [[ "$BUILD_TYPE" == "release" ]]; then
    variant_suffix="Release"
  fi

  local incremental_dir="$OBJ_DIR/gradle/build/mobile/android/fenix/app/intermediates/incremental/generateSafeArgs${variant_suffix}"
  mkdir -p "$incremental_dir"
}

require_signing_inputs() {
  if [[ -z "$KEYSTORE" && -z "$KEY_ALIAS" && -z "$STORE_PASSWORD_ENV" && -z "$KEY_PASSWORD_ENV" ]]; then
    return 0
  fi

  if [[ -z "$KEYSTORE" || -z "$KEY_ALIAS" || -z "$STORE_PASSWORD_ENV" ]]; then
    echo "[✗] Error: signing a release APK requires --keystore, --key-alias, and --store-password-env" >&2
    exit 1
  fi

  if [[ ! -f "$KEYSTORE" ]]; then
    echo "[✗] Error: keystore not found: $KEYSTORE" >&2
    exit 1
  fi

  if [[ -z "${!STORE_PASSWORD_ENV:-}" ]]; then
    echo "[✗] Error: environment variable $STORE_PASSWORD_ENV is not set" >&2
    exit 1
  fi

  if [[ -n "$KEY_PASSWORD_ENV" && -z "${!KEY_PASSWORD_ENV:-}" ]]; then
    echo "[✗] Error: environment variable $KEY_PASSWORD_ENV is not set" >&2
    exit 1
  fi
}

sign_release_apk() {
  local input_apk="$1"
  local zipalign_tool
  local apksigner_tool
  local aligned_apk
  local signed_apk
  local args

  zipalign_tool="$(find_sdk_tool zipalign)"
  apksigner_tool="$(find_sdk_tool apksigner)"

  if [[ -z "$zipalign_tool" || -z "$apksigner_tool" ]]; then
    echo "[✗] Error: zipalign/apksigner not found under $SDK_ROOT/build-tools" >&2
    exit 1
  fi

  aligned_apk="${input_apk%.apk}-aligned.apk"
  signed_apk="${input_apk%.apk}-signed.apk"

  "$zipalign_tool" -f -p 4 "$input_apk" "$aligned_apk"

  args=(
    sign
    --ks "$KEYSTORE"
    --ks-key-alias "$KEY_ALIAS"
    --ks-pass "env:$STORE_PASSWORD_ENV"
    --out "$signed_apk"
  )

  if [[ -n "$KEY_PASSWORD_ENV" ]]; then
    args+=(--key-pass "env:$KEY_PASSWORD_ENV")
  fi

  "$apksigner_tool" "${args[@]}" "$aligned_apk"
  "$apksigner_tool" verify "$signed_apk" >/dev/null

  echo "$signed_apk"
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      BUILD_TYPE="debug"
      shift
      ;;
    --prod)
      BUILD_TYPE="release"
      shift
      ;;
    --target)
      TARGET_TRIPLE="${2:-}"
      shift 2
      ;;
    --sdk-root)
      SDK_ROOT="${2:-}"
      shift 2
      ;;
    --objdir)
      OBJ_DIR="${2:-}"
      shift 2
      ;;
    --mozconfig)
      CUSTOM_MOZCONFIG="${2:-}"
      shift 2
      ;;
    --keystore)
      KEYSTORE="${2:-}"
      shift 2
      ;;
    --key-alias)
      KEY_ALIAS="${2:-}"
      shift 2
      ;;
    --store-password-env)
      STORE_PASSWORD_ENV="${2:-}"
      shift 2
      ;;
    --key-password-env)
      KEY_PASSWORD_ENV="${2:-}"
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
resolve_sdk_root
resolve_java_home
require_signing_inputs

if [[ -z "$OBJ_DIR" ]]; then
  OBJ_DIR="$ROOT_DIR/obj-w3ai-android-${TARGET_TRIPLE//[^A-Za-z0-9]/-}"
fi

if [[ -n "$CUSTOM_MOZCONFIG" ]]; then
  MOZCONFIG_PATH="$CUSTOM_MOZCONFIG"
else
  TEMP_DIR="$(mktemp -d)"
  MOZCONFIG_PATH="$TEMP_DIR/android.mozconfig"
  create_android_mozconfig "$MOZCONFIG_PATH" "$OBJ_DIR"
fi

if [[ ! -f "$MOZCONFIG_PATH" ]]; then
  echo "[✗] Error: MOZCONFIG not found: $MOZCONFIG_PATH" >&2
  exit 1
fi

GRADLE_TASK="app:assembleDebug"
OUTPUT_DIR=""

if [[ "$BUILD_TYPE" == "release" ]]; then
  GRADLE_TASK="app:assembleRelease"
fi

echo "=========================================="
echo "W3Ai Android Build"
echo "=========================================="
echo ""
echo "Build type:  $BUILD_TYPE"
echo "Target:      $TARGET_TRIPLE"
echo "SDK root:    $SDK_ROOT"
echo "MOZCONFIG:   $MOZCONFIG_PATH"
echo ""

echo "[1/3] Configuring Android build context"
MOZCONFIG="$MOZCONFIG_PATH" ./mach configure
echo "[✓] Configure complete"
echo ""

echo "[2/3] Building Gecko for Android"
MOZCONFIG="$MOZCONFIG_PATH" ./mach build
echo "[✓] Gecko build complete"
echo ""

echo "[3/3] Running $GRADLE_TASK"
prepare_gradle_intermediates
MOZCONFIG="$MOZCONFIG_PATH" ./mach gradle -p mobile/android/fenix "$GRADLE_TASK"
echo "[✓] Gradle build complete"
echo ""

RESOLVED_OBJ_DIR="$OBJ_DIR"
if [[ "$RESOLVED_OBJ_DIR" != /* ]]; then
  RESOLVED_OBJ_DIR="$ROOT_DIR/$RESOLVED_OBJ_DIR"
fi

OUTPUT_DIR_CANDIDATES=(
  "$RESOLVED_OBJ_DIR/gradle/build/mobile/android/fenix/app/outputs/apk/$BUILD_TYPE"
  "$ROOT_DIR/mobile/android/fenix/app/build/outputs/apk/$BUILD_TYPE"
)

for candidate in "${OUTPUT_DIR_CANDIDATES[@]}"; do
  if [[ -d "$candidate" ]]; then
    OUTPUT_DIR="$candidate"
    break
  fi
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "[✗] Error: Android output directory not found. Checked:" >&2
  for candidate in "${OUTPUT_DIR_CANDIDATES[@]}"; do
    echo "    - $candidate" >&2
  done
  exit 1
fi

echo "Resolved output dir: $OUTPUT_DIR"

SELECTED_APK=""
if [[ "$BUILD_TYPE" == "debug" ]]; then
  SELECTED_APK="$(ls -t "$OUTPUT_DIR"/*.apk 2>/dev/null | head -n 1 || true)"
else
  SELECTED_APK="$(ls -t "$OUTPUT_DIR"/*universal*release*.apk "$OUTPUT_DIR"/*.apk 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$SELECTED_APK" || ! -f "$SELECTED_APK" ]]; then
  echo "[✗] Error: APK not found under $OUTPUT_DIR" >&2
  exit 1
fi

if [[ "$BUILD_TYPE" == "release" && -n "$KEYSTORE" ]]; then
  echo "[2/2] Signing release APK"
  SELECTED_APK="$(sign_release_apk "$SELECTED_APK")"
  echo "[✓] APK signing complete"
  echo ""
fi

echo "=========================================="
echo "✓ Android build complete"
echo "=========================================="
echo ""
echo "Artifact ready: $SELECTED_APK"
ls -lh "$SELECTED_APK"
echo ""
echo "All APK outputs:"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.apk" -type f -print | sort
echo ""
echo "Installation on device:"
echo "  adb install -r '$SELECTED_APK'"
echo ""
