#!/usr/bin/env bash
set -euo pipefail

# Generate immutable TMRW Browser artifact names.
# Do not use date-only artifact names for updater assets. Multiple builds on the
# same day must never reuse the same MAR URL, otherwise clients can cache or
# download a different file than the one described by update.xml.
#
# Usage:
#   scripts/tmrw-release-names.sh 1.0.20260629 20260629064709
#
# Optional env:
#   PRODUCT_NAME="TMRW-Browser"
#   PRINT_EXPORTS=1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

version="${1:-${RELEASE_VERSION:-}}"
build_id="${2:-${BUILD_ID:-}}"
product="${PRODUCT_NAME:-TMRW-Browser}"

[ -n "$version" ] || fail "release version is required"
[ -n "$build_id" ] || fail "build id is required"

case "$version" in
  *[!0-9.]*|'') fail "version must contain only digits and dots: $version" ;;
esac

case "$build_id" in
  *[!0-9]*|'') fail "build id must contain only digits: $build_id" ;;
esac

base="${product}-v${version}-build${build_id}"
dmg="${base}.dmg"
mar="${base}.complete.mar"
xml="update-${version}-build${build_id}.xml"
latest_dmg="${product}-latest.dmg"
latest_xml="update.xml"

if [ "${PRINT_EXPORTS:-0}" = "1" ]; then
  cat <<EOF
export TMRW_RELEASE_VERSION="$version"
export TMRW_BUILD_ID="$build_id"
export TMRW_ARTIFACT_BASE="$base"
export TMRW_DMG_NAME="$dmg"
export TMRW_COMPLETE_MAR_NAME="$mar"
export TMRW_VERSIONED_UPDATE_XML_NAME="$xml"
export TMRW_LATEST_DMG_ALIAS="$latest_dmg"
export TMRW_LIVE_UPDATE_XML_NAME="$latest_xml"
EOF
else
  cat <<EOF
release_version=$version
build_id=$build_id
artifact_base=$base
dmg=$dmg
complete_mar=$mar
versioned_update_xml=$xml
latest_dmg_alias=$latest_dmg
live_update_xml=$latest_xml
EOF
fi
