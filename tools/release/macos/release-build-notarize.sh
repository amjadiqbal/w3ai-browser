#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  release-build-notarize.sh [options]

This script builds and packages Firefox/W3Ai on macOS, then notarizes the latest DMG.

Options:
  --objdir <path>               Optional object directory to search for DMGs
  --dmg <path>                  Optional explicit DMG path (skips auto-detect)
  --keychain-profile <name>     notarytool keychain profile
  --apple-id <id>               Apple ID (if not using keychain profile)
  --team-id <id>                Apple Developer Team ID
  --signing-identity <name>     Optional DMG signing identity
  --dry-run                     Build/package and validation only (no notarization)
  -h, --help                    Show help
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
OBJ_DIR=""
DMG_PATH=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --objdir)
      OBJ_DIR="${2:-}"
      shift 2
      ;;
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      if [[ $# -gt 1 && ! "${2:-}" =~ ^-- ]]; then
        EXTRA_ARGS+=("$2")
        shift 2
      else
        shift
      fi
      ;;
  esac
done

cd "$ROOT_DIR"

echo "[1/4] Build"
./mach build

echo "[2/4] Package"
./mach package

if [[ -z "$DMG_PATH" ]]; then
  echo "[3/4] Detect latest DMG"
  if [[ -n "$OBJ_DIR" ]]; then
    DMG_PATH="$(ls -t "$OBJ_DIR"/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  else
    DMG_PATH="$(ls -t obj-*/dist/*.dmg 2>/dev/null | head -n 1 || true)"
  fi
fi

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Could not find a DMG. Provide --dmg or --objdir explicitly." >&2
  exit 1
fi

echo "Detected DMG: $DMG_PATH"

echo "[4/4] Sign/Notarize"
"$ROOT_DIR/tools/release/macos/sign-and-notarize-dev.sh" --dmg "$DMG_PATH" "${EXTRA_ARGS[@]}"

echo "Release build + notarization completed."
