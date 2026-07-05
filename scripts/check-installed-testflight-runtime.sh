#!/usr/bin/env bash
set -uo pipefail

# check-installed-testflight-runtime.sh — check a *running* installed TMRW.app
# for development/build-machine sandbox paths leaking into child process
# launch arguments (found 2026-07-05: MozillaDeveloperRepoPath/
# MozillaDeveloperObjPath in Info.plist were being read at runtime and passed
# to every content/GMP child process as -sbTestingReadPath <build machine
# path>, widening the App Sandbox with read access to the developer's local
# filesystem). scripts/package-testflight-macos.sh now repoints those
# Info.plist keys at a safe in-bundle path — this script verifies that held
# at actual runtime, not just in the shipped files.
#
# Usage:
#   ./scripts/check-installed-testflight-runtime.sh
#
# Requires TMRW.app to already be running with at least one tab open (so a
# content process has actually launched).

fail_count=0
note() { echo "==> $*"; }
check_fail() { echo "FAIL: $*" >&2; fail_count=$((fail_count + 1)); }

note "Checking running TMRW/firefox/plugin-container/gpu-helper process args"

ps_output="$(ps auxww | grep -E "TMRW|firefox|plugin-container|gpu-helper|media-plugin-helper|security-module-helper" | grep -v grep)"

if [ -z "$ps_output" ]; then
  echo "No TMRW/firefox/plugin-container/helper processes are currently running."
  echo "Open TMRW.app and load a page first, then re-run this check."
  exit 1
fi

echo "$ps_output"
echo ""

leaked_lines="$(echo "$ps_output" | grep -E -- "-sbTestingReadPath|/Volumes/Amjad/Plato/W3Ai|obj-x86_64-apple-darwin25.5.0" || true)"

if [ -n "$leaked_lines" ]; then
  check_fail "TestFlight runtime is using development sandbox read paths:"
  echo "$leaked_lines" >&2
else
  note "No development sandbox read paths found in running process args"
fi

note "Checking child processes actually launched (content/GPU/plugin-container)"
if ! echo "$ps_output" | grep -q "plugin-container"; then
  check_fail "No plugin-container process is running — content processes may not be launching at all"
else
  note "plugin-container process(es) present"
fi

echo ""
echo "==================================================================="
if [ "$fail_count" -gt 0 ]; then
  echo "RESULT: $fail_count check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
