#!/usr/bin/env bash
# scripts/lib/ui.sh — Terminal UI: progress bars, spinners, step headers

# ── ANSI colors ───────────────────────────────────────────────────────────────
UI_RED='\033[0;31m'
UI_GREEN='\033[0;32m'
UI_YELLOW='\033[1;33m'
UI_CYAN='\033[0;36m'
UI_WHITE='\033[0;37m'
UI_BOLD='\033[1m'
UI_DIM='\033[2m'
UI_RESET='\033[0m'

# ── Internal: repeat a character N times ──────────────────────────────────────
_ui_repeat() {
  local char="$1" n="$2" out=""
  while (( n-- > 0 )); do out+="$char"; done
  printf '%s' "$out"
}

# ── Banner ────────────────────────────────────────────────────────────────────
# Usage: ui_banner "TMRW Browser v1.0.20260624 — publishing update"
ui_banner() {
  local msg="$1" width=60
  local pad=$(( (width - ${#msg}) / 2 ))
  local line
  line=$(_ui_repeat '─' "$width")
  printf "\n${UI_BOLD}${UI_CYAN}┌%s┐${UI_RESET}\n" "$line"
  printf "${UI_BOLD}${UI_CYAN}│%*s%s%*s│${UI_RESET}\n" "$pad" "" "$msg" "$(( width - pad - ${#msg} ))" ""
  printf "${UI_BOLD}${UI_CYAN}└%s┘${UI_RESET}\n\n" "$line"
}

# ── Step header ───────────────────────────────────────────────────────────────
# Usage: ui_step 2 5 "Creating MAR package"
ui_step() {
  local n="$1" total="$2" label="$3"
  printf "\n${UI_BOLD}${UI_CYAN}[%d/%d]${UI_RESET} ${UI_BOLD}%s${UI_RESET}\n" "$n" "$total" "$label"
}

# ── Status lines ──────────────────────────────────────────────────────────────
ui_ok()   { printf "      ${UI_GREEN}✓${UI_RESET}  %s\n" "$1"; }
ui_warn() { printf "      ${UI_YELLOW}!${UI_RESET}  %s\n" "$1"; }
ui_fail() { printf "      ${UI_RED}✗${UI_RESET}  %s\n" "$1"; }
ui_info() { printf "      ${UI_DIM}→${UI_RESET}  %s\n" "$1"; }

# ── Spinner ───────────────────────────────────────────────────────────────────
_UI_SPINNER_PID=""
_UI_SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

ui_spinner_start() {
  local msg="$1"
  printf ""
  (
    local i=0
    while true; do
      printf "\r      ${UI_CYAN}%s${UI_RESET}  ${UI_DIM}%s${UI_RESET}  " \
        "${_UI_SPINNER_FRAMES[$(( i % ${#_UI_SPINNER_FRAMES[@]} ))]}" "$msg"
      (( i++ ))
      sleep 0.08
    done
  ) &
  _UI_SPINNER_PID=$!
  disown "$_UI_SPINNER_PID" 2>/dev/null || true
}

ui_spinner_stop() {
  local result="${1:-ok}"  # ok | fail | warn
  if [[ -n "$_UI_SPINNER_PID" ]]; then
    kill "$_UI_SPINNER_PID" 2>/dev/null || true
    wait "$_UI_SPINNER_PID" 2>/dev/null || true
    _UI_SPINNER_PID=""
  fi
  case "$result" in
    ok)   printf "\r      ${UI_GREEN}✓${UI_RESET}  Done%-50s\n" "" ;;
    fail) printf "\r      ${UI_RED}✗${UI_RESET}  Failed%-48s\n" "" ;;
    warn) printf "\r      ${UI_YELLOW}!${UI_RESET}  Warning%-47s\n" "" ;;
  esac
}

# ── Upload progress bar ───────────────────────────────────────────────────────
# Internal: draw the 5-line progress block (or redraw it in place)
_UI_PROG_DRAWN=0
_ui_draw_bar() {
  local pct="$1" up_mb="$2" total_mb="$3" speed_mb="$4" eta="$5" label="$6"
  local bar_width=44 filled empty

  filled=$(awk "BEGIN{n=int($pct*$bar_width/100); if(n>$bar_width)n=$bar_width; if(n<0)n=0; print n}")
  empty=$(( bar_width - filled ))

  local bar_f bar_e
  bar_f=$(_ui_repeat '█' "$filled")
  bar_e=$(_ui_repeat '░' "$empty")

  # Format ETA
  local eta_str
  if [[ "$eta" == "--" ]]; then
    eta_str="calculating…"
  elif (( $(awk "BEGIN{print ($eta < 60) ? 1 : 0}") )); then
    eta_str="${eta}s"
  else
    eta_str="$(( eta / 60 ))m $(( eta % 60 ))s"
  fi

  # Erase previous block if already drawn
  if (( _UI_PROG_DRAWN )); then
    printf "\033[5A"
  fi

  printf "\033[2K  ${UI_BOLD}%s${UI_RESET}\n"                                           "$label"
  printf "\033[2K  ${UI_CYAN}%s${UI_DIM}%s${UI_RESET}  ${UI_BOLD}%.0f%%${UI_RESET}\n"  "$bar_f" "$bar_e" "$pct"
  printf "\033[2K\n"
  printf "\033[2K  ${UI_DIM}Uploaded  ${UI_RESET}${UI_WHITE}%6.1f MB${UI_RESET} ${UI_DIM}/ %.1f MB${UI_RESET}\n" \
    "$up_mb" "$total_mb"
  printf "\033[2K  ${UI_DIM}Speed     ${UI_RESET}${UI_YELLOW}%6.1f MB/s${UI_RESET}   ${UI_DIM}ETA ${UI_RESET}${UI_WHITE}%s${UI_RESET}\n" \
    "$speed_mb" "$eta_str"

  _UI_PROG_DRAWN=1
}

# Public: upload a file with live progress bar
# Usage: ui_upload_with_progress URL FILE LABEL VERSION
# Reads PUBLISH_SECRET from environment.
# Echoes http status code on stdout (last line).
# Returns 0 on HTTP 200, 1 otherwise.
ui_upload_with_progress() {
  local url="$1" file="$2" label="$3" version="$4"

  local file_size total_mb
  file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 1)
  total_mb=$(awk "BEGIN{printf \"%.1f\", $file_size/1048576}")

  _UI_PROG_DRAWN=0

  local response_file
  response_file=$(mktemp)

  ui_info "Uploading ${label} (${total_mb} MB)…" >&2

  # Run curl in foreground — backgrounding + stderr redirect silently drops the
  # HTTP status code when the shell is non-interactive (publish-update.sh context).
  local http_code response
  http_code=$(curl -s \
    -X POST "$url" \
    -H "Authorization: Bearer $PUBLISH_SECRET" \
    -F "version=$version" \
    -F "file=@$file;type=application/octet-stream" \
    --max-time 1800 \
    -o "$response_file" \
    -w "%{http_code}" \
    2>/dev/null || echo "000")
  response=$(cat "$response_file" 2>/dev/null || echo "")

  rm -f "$response_file"

  # UI output goes to stderr so callers using $(...) capture only the HTTP code
  if [[ "$http_code" == "200" ]]; then
    local resp_url
    resp_url=$(echo "$response" | python3 -c \
      "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)
    [[ -n "$resp_url" ]] && ui_ok "Available at: $resp_url" >&2
    printf '%s' "$http_code"
    return 0
  else
    ui_fail "HTTP $http_code — $response" >&2
    printf '%s' "$http_code"
    return 1
  fi
}
