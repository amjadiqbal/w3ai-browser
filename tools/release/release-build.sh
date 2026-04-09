#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  release-build.sh <platform> [options]

W3Ai Universal Release Builder
Build and package W3Ai for macOS, Android, or iOS with a single command.

Platforms:
  macos-dev        macOS development build (unsigned DMG)
  macos-prod       macOS production build (signed + notarized DMG)
  android          Android APK (dev or prod mode)
  ios              iOS IPA (dev or prod mode)

Examples:
  # macOS development (test on device, no signing)
  ./tools/release/release-build.sh macos-dev

  # macOS production (sign + notarize for distribution)
  ./tools/release/release-build.sh macos-prod --keychain-profile my-profile

  # Android development build
  ./tools/release/release-build.sh android --dev

  # iOS production build
  ./tools/release/release-build.sh ios --prod --team-id ABCD123456

Platform-Specific Options:
  macos-dev:
    --no-dmg          Skip DMG creation
    --objdir <path>   Object directory

  macos-prod:
    --keychain-profile <name>   notarytool keychain profile
    --apple-id <id>             Apple ID (without keychain-profile)
    --team-id <id>              Apple Developer Team ID
    --signing-identity <name>   DMG signing identity
    --no-notarize               Sign but don't notarize
    --objdir <path>             Object directory
    --dmg <path>                Explicit DMG path

  android, ios:
    --dev / --prod              Build type
    --objdir <path>             Object directory

For detailed help on each platform:
  ./tools/release/macos/build-dev.sh --help
  ./tools/release/macos/build-prod.sh --help
  ./tools/release/android/build.sh --help
  ./tools/release/ios/build.sh --help
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

PLATFORM="$1"
shift

ROOT_DIR="$(cd "$(dirname "$0")/../release/" && pwd)"

case "$PLATFORM" in
  macos-dev)
    exec "$ROOT_DIR/macos/build-dev.sh" "$@"
    ;;
  macos-prod)
    exec "$ROOT_DIR/macos/build-prod.sh" "$@"
    ;;
  android)
    exec "$ROOT_DIR/android/build.sh" "$@"
    ;;
  ios)
    exec "$ROOT_DIR/ios/build.sh" "$@"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown platform: $PLATFORM" >&2
    usage >&2
    exit 1
    ;;
esac
