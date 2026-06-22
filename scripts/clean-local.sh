#!/usr/bin/env bash
# clean-local.sh — Remove TMRW Browser installation and all local profile/cache data
#
# Usage:
#   ./scripts/clean-local.sh              # interactive — asks before deleting
#   ./scripts/clean-local.sh --all        # remove app + profiles + caches (no prompt)
#   ./scripts/clean-local.sh --profiles   # profiles + caches only (keep app)
#   ./scripts/clean-local.sh --caches     # caches only (fastest reset)

set -euo pipefail

APP_NAME="TMRW Browser"
APP_PATH="/Applications/${APP_NAME}.app"

# Paths controlled by Gecko profile system (uses "Firefox" dir because we
# never set MOZ_APP_PROFILE in branding — will be fixed in a future release)
PROFILE_DIR=~/Library/Application\ Support/Firefox
MOZILLA_DIR=~/Library/Application\ Support/Mozilla
CACHE_DIR=~/Library/Caches/Firefox
LOGS_DIR=~/Library/Logs/W3AI\ by\ Plato

# ── Parse flags ────────────────────────────────────────────────────────────────
MODE="${1:-}"

print_summary() {
  echo ""
  echo "What will be removed:"
  echo ""
  if [[ "$MODE" != "--profiles" && "$MODE" != "--caches" ]]; then
    [[ -d "$APP_PATH" ]] \
      && echo "  App       $(du -sh "$APP_PATH" 2>/dev/null | cut -f1)  $APP_PATH" \
      || echo "  App       (not installed)"
  fi
  if [[ "$MODE" != "--caches" ]]; then
    [[ -d "$PROFILE_DIR" ]] \
      && echo "  Profiles  $(du -sh "$PROFILE_DIR" 2>/dev/null | cut -f1)  $PROFILE_DIR" \
      || echo "  Profiles  (not found)"
    [[ -d "$MOZILLA_DIR" ]] \
      && echo "  Mozilla   $(du -sh "$MOZILLA_DIR" 2>/dev/null | cut -f1)  $MOZILLA_DIR" \
      || echo "  Mozilla   (not found)"
  fi
  [[ -d "$CACHE_DIR" ]] \
    && echo "  Caches    $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)  $CACHE_DIR" \
    || echo "  Caches    (not found)"
  [[ -d "$LOGS_DIR" ]] \
    && echo "  Logs      $(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)  $LOGS_DIR" \
    || echo "  Logs      (not found)"
  echo ""
}

# ── Guard: quit browser first ──────────────────────────────────────────────────
if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
  echo "ERROR: ${APP_NAME} is running. Quit it first, then re-run this script."
  exit 1
fi

# ── Show what will happen ──────────────────────────────────────────────────────
echo "============================================================"
echo "  TMRW Browser — local cleanup"
echo "============================================================"

print_summary

# ── Prompt if no flag given ────────────────────────────────────────────────────
if [[ -z "$MODE" ]]; then
  echo "Options:"
  echo "  1) Remove everything  (app + profiles + caches)"
  echo "  2) Profiles + caches  (keep app)"
  echo "  3) Caches only        (fastest reset, keep profiles)"
  echo "  q) Quit"
  echo ""
  read -rp "Choice [1/2/3/q]: " choice
  case "$choice" in
    1) MODE="--all" ;;
    2) MODE="--profiles" ;;
    3) MODE="--caches" ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ── Execute ────────────────────────────────────────────────────────────────────
do_remove() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "  Removed: $label"
  fi
}

echo "Cleaning..."

case "$MODE" in
  --all)
    do_remove "$APP_PATH"    "TMRW Browser.app"
    do_remove "$PROFILE_DIR" "Firefox profiles"
    do_remove "$MOZILLA_DIR" "Mozilla support"
    do_remove "$CACHE_DIR"   "Firefox caches"
    do_remove "$LOGS_DIR"    "W3AI logs"
    ;;
  --profiles)
    do_remove "$PROFILE_DIR" "Firefox profiles"
    do_remove "$MOZILLA_DIR" "Mozilla support"
    do_remove "$CACHE_DIR"   "Firefox caches"
    do_remove "$LOGS_DIR"    "W3AI logs"
    ;;
  --caches)
    do_remove "$CACHE_DIR"   "Firefox caches"
    ;;
  *)
    echo "ERROR: Unknown flag: $MODE"
    echo "Usage: $0 [--all | --profiles | --caches]"
    exit 1
    ;;
esac

echo ""
echo "Done. Install the latest TMRW Browser DMG from:"
echo "  https://tmrw.w3ai.io/download"
echo ""
