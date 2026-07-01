#!/usr/bin/env bash
# build-updater.sh — Compile org.mozilla.updater with no MAR signature verification.
#
# TMRW uses a custom updater so we can distribute MAR update packages without
# needing Mozilla's private signing keys.  The updater accepts any valid MAR file.
#
# Run after ./mach build faster whenever the updater binary needs refreshing.
# Output: replaces org.mozilla.updater in all locations under dist/.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$REPO/obj-x86_64-apple-darwin25.5.0"
SDK="$(xcrun --show-sdk-path)"
CXX="$(xcrun -f clang++)"
CC="$(xcrun -f clang)"
OUT="$(mktemp -d)"
VERSION="$(tr -d '[:space:]' < "$REPO/browser/config/version.txt")"

echo "Building org.mozilla.updater v$VERSION (no MAR signature check)..."

# Ensure mfbt headers are available as mozilla/*.h
MOZILLA_INC=/tmp/mozilla-includes/mozilla
mkdir -p "$MOZILLA_INC"
for h in "$REPO/mfbt/"*.h; do
  [[ -f "$MOZILLA_INC/$(basename "$h")" ]] || /bin/cp "$h" "$MOZILLA_INC/"
done
/bin/cp "$REPO/toolkit/xre/CmdLineAndEnvUtils.h" "$MOZILLA_INC/" 2>/dev/null || true
/bin/cp "$REPO/mozglue/misc/Sprintf.h" "$MOZILLA_INC/" 2>/dev/null || true
/bin/cp "$REPO/mozglue/misc/Printf.h" "$MOZILLA_INC/" 2>/dev/null || true

compile() {
  local SRC="$1" OBJ_OUT="$2"
  "$CXX" \
    --sysroot="$SDK" \
    -DMOZ_WIDGET_COCOA=1 -DXP_MACOSX=1 -DXP_UNIX=1 -DXP_DARWIN=1 \
    -DMOZ_UPDATER=1 -DMOZ_BSPATCH=1 \
    -DNS_NO_XPCOM=1 \
    -DMOZ_APP_VERSION="\"$VERSION\"" -DMOZ_UPDATE_CHANNEL=default \
    -DMOZ_APP_BASENAME='"TMRWBrowser"' \
    -std=c++20 -O2 -arch x86_64 \
    -I"$REPO/toolkit/mozapps/update/updater" \
    -I"$REPO/toolkit/mozapps/update/updater/bspatch" \
    -I"$REPO/toolkit/mozapps/update/updater/macos-frameworks" \
    -I"$REPO/toolkit/mozapps/update/updater/macos-frameworks/UpdateSettings" \
    -I"$REPO/toolkit/mozapps/update/common" \
    -I"$REPO/toolkit/xre" \
    -I"$OBJ/toolkit/mozapps/update/updater" \
    -I"$REPO/modules/libmar/src" \
    -I"$REPO/modules/libmar/verify" \
    -I"$REPO/modules/xz-embedded/src" \
    -I"$REPO/xpcom/base" \
    -I/tmp/mozilla-includes \
    -I"$REPO/other-licenses/nsis/Contrib/CityHash/cityhash" \
    -c "$SRC" -o "$OBJ_OUT" 2>&1 | grep -v "^$REPO" | grep -v "^/Library" | grep "error:" || true
  return "${PIPESTATUS[0]}"
}

compile_c() {
  local SRC="$1" OBJ_OUT="$2"
  "$CC" \
    --sysroot="$SDK" \
    -DMOZ_WIDGET_COCOA=1 -DXP_MACOSX=1 -DXP_UNIX=1 -DXP_DARWIN=1 \
    -std=c11 -O2 -arch x86_64 \
    -I"$REPO/modules/libmar/src" \
    -I"$REPO/modules/xz-embedded/src" \
    -I"$REPO/other-licenses/nsis/Contrib/CityHash/cityhash" \
    -c "$SRC" -o "$OBJ_OUT" 2>&1 | grep "error:" || true
  return "${PIPESTATUS[0]}"
}

echo "  Compiling C++ sources..."
compile "$REPO/toolkit/mozapps/update/updater/archivereader.cpp"  "$OUT/archivereader.o"
compile "$REPO/toolkit/mozapps/update/updater/bspatch/bspatch.cpp" "$OUT/bspatch.o"
compile "$REPO/toolkit/mozapps/update/updater/updater.cpp"         "$OUT/updater.o"
compile "$REPO/toolkit/mozapps/update/common/updatecommon.cpp"     "$OUT/updatecommon.o"
compile "$REPO/toolkit/mozapps/update/common/readstrings.cpp"      "$OUT/readstrings.o"
compile "$REPO/other-licenses/nsis/Contrib/CityHash/cityhash/city.cpp" "$OUT/city.o"

echo "  Compiling Objective-C++ sources..."
compile "$REPO/toolkit/xre/updaterfileutils_osx.mm"                      "$OUT/updaterfileutils_osx.o"
compile "$REPO/toolkit/mozapps/update/updater/launchchild_osx.mm"         "$OUT/launchchild_osx.o"
compile "$REPO/toolkit/mozapps/update/updater/macos-frameworks/UpdateSettingsUtil.mm" "$OUT/UpdateSettingsUtil.o"

# UpdateSettings.mm needs ACCEPTED_MAR_CHANNEL_IDS
"$CXX" --sysroot="$SDK" -std=c++17 -O2 -arch x86_64 \
  -DMOZ_WIDGET_COCOA=1 -DXP_MACOSX=1 \
  '-DACCEPTED_MAR_CHANNEL_IDS="default"' \
  -I"$REPO/toolkit/mozapps/update/updater/macos-frameworks/UpdateSettings" \
  -c "$REPO/toolkit/mozapps/update/updater/macos-frameworks/UpdateSettings/UpdateSettings.mm" \
  -o "$OUT/UpdateSettings.o" 2>&1 | grep "error:" || true

# Progress UI stub (macOS signature: ShowProgressUI(bool))
cat > /tmp/progressui_macos_stub.mm << 'EOF'
#include "progressui.h"
int InitProgressUI(int* argc, NS_tchar*** argv) { return 0; }
int ShowProgressUI(bool indeterminate) { return 0; }
void QuitProgressUI() {}
void UpdateProgressUI(float progress) {}
EOF
compile /tmp/progressui_macos_stub.mm "$OUT/progressui.o"

echo "  Compiling C sources..."
for f in mar_read.c mar_create.c mar_extract.c; do
  compile_c "$REPO/modules/libmar/src/$f" "$OUT/${f%.c}.o"
done
for f in xz_crc32.c xz_crc64.c xz_dec_bcj.c xz_dec_lzma2.c xz_dec_stream.c; do
  compile_c "$REPO/modules/xz-embedded/src/$f" "$OUT/${f%.c}.o"
done

echo "  Linking..."
"$CXX" \
  --sysroot="$SDK" \
  -arch x86_64 \
  -o "$OUT/org.mozilla.updater" \
  "$OUT"/*.o \
  -framework Cocoa -framework Foundation -framework Security -framework SystemConfiguration \
  -lbz2 -lz 2>&1 | grep "error:" || true

echo "  Replacing updater binaries..."
for p in \
  "$OBJ/dist/TMRW Browser.app/Contents/MacOS/updater.app/Contents/MacOS/org.mozilla.updater" \
  "$OBJ/dist/TMRW Browser.app/Contents/Library/LaunchServices/org.mozilla.updater" \
  "$OBJ/dist/TMRW Browser.app/Contents/Resources/org.mozilla.updater" \
  "$OBJ/dist/firefox/TMRW Browser.app/Contents/Library/LaunchServices/org.mozilla.updater" \
  "$OBJ/dist/bin/org.mozilla.updater" \
  "$OBJ/dist/bin/updater.app/Contents/MacOS/org.mozilla.updater"
do
  if [[ -f "$p" ]]; then
    /bin/cp "$OUT/org.mozilla.updater" "$p"
    /bin/chmod 755 "$p"
    echo "    Replaced: $(basename "$(dirname "$p")")/$(basename "$p")"
  fi
done

rm -rf "$OUT"
echo "Done. org.mozilla.updater ($VERSION) installed — no MAR signature check."
