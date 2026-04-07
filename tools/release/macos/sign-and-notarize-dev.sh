#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sign-and-notarize-dev.sh --dmg <path> [options]

Required:
  --dmg <path>                  Path to the DMG file

Notarization auth (choose one mode):
  --keychain-profile <name>     notarytool keychain profile name
  --apple-id <id>               Apple ID email
  --team-id <id>                Apple Developer Team ID

Optional:
  --signing-identity <name>     Sign DMG before notarization
  --dry-run                     Validate only, skip notarization
  -h, --help                    Show this help

Environment fallback:
  APPLE_ID, APPLE_PASSWORD, APPLE_TEAM, NOTARY_PROFILE, SIGNING_IDENTITY
EOF
}

DMG_PATH=""
APPLE_ID_ARG="${APPLE_ID:-}"
APPLE_PASSWORD_ARG="${APPLE_PASSWORD:-}"
TEAM_ID_ARG="${APPLE_TEAM:-}"
PROFILE_ARG="${NOTARY_PROFILE:-}"
SIGNING_IDENTITY_ARG="${SIGNING_IDENTITY:-}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --apple-id)
      APPLE_ID_ARG="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID_ARG="${2:-}"
      shift 2
      ;;
    --keychain-profile)
      PROFILE_ARG="${2:-}"
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY_ARG="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$DMG_PATH" ]]; then
  echo "Missing required --dmg argument" >&2
  usage
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG file not found: $DMG_PATH" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but not found" >&2
  exit 1
fi

if [[ -n "$PROFILE_ARG" ]]; then
  AUTH_MODE="profile"
else
  AUTH_MODE="appleid"
  if [[ -z "$APPLE_ID_ARG" || -z "$TEAM_ID_ARG" ]]; then
    echo "Missing notarization credentials. Provide --keychain-profile or --apple-id with --team-id." >&2
    exit 1
  fi

  if [[ -z "$APPLE_PASSWORD_ARG" ]]; then
    read -r -s -p "Apple app-specific password (input hidden): " APPLE_PASSWORD_ARG
    echo
  elif [[ -n "${APPLE_PASSWORD:-}" ]]; then
    echo "Warning: APPLE_PASSWORD is set in environment; prefer --keychain-profile for local use." >&2
  fi
fi

echo "[1/5] Validating DMG: $DMG_PATH"
ls -lh "$DMG_PATH"

if [[ -n "$SIGNING_IDENTITY_ARG" ]]; then
  echo "[2/5] Signing DMG with identity: $SIGNING_IDENTITY_ARG"
  codesign --force --sign "$SIGNING_IDENTITY_ARG" "$DMG_PATH"
else
  echo "[2/5] Skipping DMG signing (no --signing-identity provided)"
fi

echo "[3/5] Running local signature gate check"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[4/5] Dry run enabled; skipping notarization and stapling"
  echo "[5/5] Done (validation only)"
  exit 0
fi

echo "[4/5] Submitting DMG to Apple notarization service"
if [[ "$AUTH_MODE" == "profile" ]]; then
  xcrun notarytool submit "$DMG_PATH" --wait --keychain-profile "$PROFILE_ARG"
else
  xcrun notarytool submit "$DMG_PATH" --wait \
    --apple-id "$APPLE_ID_ARG" \
    --password "$APPLE_PASSWORD_ARG" \
    --team-id "$TEAM_ID_ARG"
fi

echo "[5/5] Stapling notarization ticket and final verify"
xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

echo "Notarization pipeline complete for: $DMG_PATH"
