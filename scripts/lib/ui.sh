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

  local progress_file status_file response_file
  progress_file=$(mktemp)
  status_file=$(mktemp)
  response_file=$(mktemp)

  # Initial display (0%)
  _ui_draw_bar 0 0 "$total_mb" 0 "--" "$label"

  local start_ns
  start_ns=$(python3 -c "import time; print(int(time.time_ns()))" 2>/dev/null || \
             awk 'BEGIN{print int(systime() * 1e9)}')

  # Run curl in background; -# writes progress to stderr as '#####  XX.X%\r'
  (
    curl \
      -X POST "$url" \
      -H "Authorization: Bearer $PUBLISH_SECRET" \
      -F "version=$version" \
      -F "file=@$file;type=application/octet-stream" \
      --progress-bar \
      --max-time 1800 \
      --retry 2 \
      --retry-delay 5 \
      -o "$response_file" \
      -w "%{http_code}" \
      2>"$progress_file" \
    > "$status_file"
  ) &
  local curl_pid=$!

  # ── Monitor loop ────────────────────────────────────────────────────────────
  local pct=0 speed_mb=0 eta="--"
  while kill -0 "$curl_pid" 2>/dev/null; do
    # curl -# writes "######  XX.X%\r" to stderr; grab the latest percentage
    local raw_pct
    raw_pct=$(tr '\r' '\n' < "$progress_file" 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9]+%' | tail -1 | tr -d '%')

    if [[ -n "$raw_pct" ]] && awk "BEGIN{exit !($raw_pct > 0)}"; then
      pct="$raw_pct"

      local now_ns elapsed_s uploaded_mb
      now_ns=$(python3 -c "import time; print(int(time.time_ns()))" 2>/dev/null || \
               awk 'BEGIN{print int(systime() * 1e9)}')
      elapsed_s=$(awk "BEGIN{printf \"%.2f\", ($now_ns - $start_ns) / 1e9}")
      uploaded_mb=$(awk "BEGIN{printf \"%.1f\", $file_size * $pct / 100 / 1048576}")

      if awk "BEGIN{exit !($elapsed_s > 0.5 && $pct > 0)}"; then
        speed_mb=$(awk "BEGIN{printf \"%.1f\", $file_size * $pct / 100 / 1048576 / $elapsed_s}")
        eta=$(awk "BEGIN{
          remaining = $file_size * (100 - $pct) / 100 / 1048576
          speed = $speed_mb + 0
          if (speed > 0) printf \"%.0f\", remaining / speed
          else print \"--\"
        }")
      fi

      _ui_draw_bar "$pct" "$uploaded_mb" "$total_mb" "$speed_mb" "$eta" "$label"
    fi

    sleep 0.25
  done

  wait "$curl_pid" 2>/dev/null || true

  # Show 100% completion
  _ui_draw_bar 100 "$total_mb" "$total_mb" "$speed_mb" 0 "$label"
  printf "\n"
  _UI_PROG_DRAWN=0

  local http_code response
  http_code=$(cat "$status_file" 2>/dev/null | tr -d '[:space:]' || echo "000")
  response=$(cat "$response_file" 2>/dev/null || echo "")

  rm -f "$progress_file" "$status_file" "$response_file"

  # Print parsed response URL
  if [[ "$http_code" == "200" ]]; then
    local resp_url
    resp_url=$(echo "$response" | python3 -c \
      "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)
    [[ -n "$resp_url" ]] && ui_ok "Available at: $resp_url"
    printf '%s' "$http_code"
    return 0
  else
    ui_fail "HTTP $http_code — $response"
    printf '%s' "$http_code"
    return 1
  fi
}
