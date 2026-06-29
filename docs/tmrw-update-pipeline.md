# TMRW Browser update pipeline

This document describes the release/update rules for the TMRW Browser Firefox/Gecko fork.

The goal is not to rewrite Firefox's updater. The goal is to feed Gecko's existing updater a clean, consistent set of release artifacts.

## Core rule

Every release has exactly one canonical pair:

```text
RELEASE_VERSION=1.0.20260629
BUILD_ID=20260629064709
```

That same pair must be present in all release outputs:

```text
TMRW Browser.app/Contents/Resources/application.ini
TMRW Browser.app/Contents/Resources/platform.ini
TMRW Browser.app/Contents/Info.plist
TMRW Browser.app/Contents/Resources/omni.ja AppConstants
complete MAR
update.xml
DMG
installed app in /Applications
```

A release must fail if any one of these values is stale or inconsistent.

## Known failure that caused the update loop

A bad build was found with:

```text
application.ini BuildID = 20260629064709
platform.ini BuildID    = 20260622143735
```

That is invalid. Gecko sees conflicting build metadata and can keep offering or staging the same update.

The pipeline must block this condition:

```text
application.ini BuildID != platform.ini BuildID
```

## Complete MAR first

Until update stability is proven, publish only complete MAR updates.

Do not debug partial MAR updates while these are still unstable:

```text
version metadata
BuildID metadata
DMG contents
server upload naming
update.xml hash/size
local staged update state
```

Partial MARs can be added later after complete MAR updates are reliable.

## Artifact names must be immutable

Do not use only the date in artifact names for updater assets.

Bad:

```text
TMRW-Browser-v1.0.20260629.dmg
TMRW-Browser-v1.0.20260629.complete.mar
```

This breaks when multiple builds happen on the same day. The Laravel update server may overwrite the existing upload, clients may cache the old file, and `update.xml` may describe a different file than the one downloaded by users.

Good:

```text
TMRW-Browser-v1.0.20260629-build20260629064709.dmg
TMRW-Browser-v1.0.20260629-build20260629064709.complete.mar
update-1.0.20260629-build20260629064709.xml
```

A stable alias is okay for manual downloads:

```text
TMRW-Browser-latest.dmg
```

But `update.xml` should point to the immutable `.complete.mar` URL, not to a same-day overwrite filename.

Use:

```bash
scripts/tmrw-release-names.sh 1.0.20260629 20260629064709
```

## Required release order

The release script should run in this order:

```text
1. Generate RELEASE_VERSION and BUILD_ID once.
2. Clean stale package artifacts for TMRW only.
3. Build/package the app.
4. Patch or regenerate application.ini, platform.ini, Info.plist, and omni.ja metadata from the same values.
5. Verify the built .app.
6. Build the complete MAR from that verified app/build output.
7. Generate update.xml using the actual MAR size and SHA512.
8. Create the DMG from the verified app.
9. Mount the DMG and verify the app inside it.
10. Upload immutable DMG/MAR/XML files to the Laravel update server.
11. Verify the live update.xml from the server.
12. Install the DMG into /Applications and verify the installed app before announcing the release.
```

## Required validation

Use:

```bash
EXPECTED_VERSION="1.0.20260629" \
EXPECTED_BUILD_ID="20260629064709" \
APP_PATH="/path/to/TMRW Browser.app" \
DMG_PATH="/path/to/TMRW-Browser-v1.0.20260629-build20260629064709.dmg" \
MAR_PATH="/path/to/TMRW-Browser-v1.0.20260629-build20260629064709.complete.mar" \
UPDATE_XML_PATH="/path/to/update.xml" \
scripts/verify-tmrw-release.sh
```

For live server verification:

```bash
EXPECTED_VERSION="1.0.20260629" \
EXPECTED_BUILD_ID="20260629064709" \
APP_PATH="/Applications/TMRW Browser.app" \
MAR_PATH="/path/to/TMRW-Browser-v1.0.20260629-build20260629064709.complete.mar" \
UPDATE_XML_URL="https://tmrw-update.w3ai.io/updates/update.xml" \
scripts/verify-tmrw-release.sh
```

## Things that must not happen

```text
Do not use date-only MAR filenames for updater URLs.
Do not publish update.xml before the MAR upload is complete.
Do not publish update.xml if the live MAR hash does not match.
Do not patch only application.ini.
Do not patch only Info.plist.
Do not patch only omni.ja.
Do not declare success until /Applications/TMRW Browser.app is verified.
Do not test updates by running the app directly from the mounted DMG.
Do not move to partial MAR until complete MAR succeeds reliably.
```

## Local update-state cleanup for testing

When testing new builds after bad update attempts, clear stale local update state once before retesting:

```bash
pkill -f "TMRW" || true
find ~/Library/Caches -iname "update.status" -print
find ~/Library/Caches -iname "active-update.xml" -print
find ~/Library/Caches -iname "updates.xml" -print
find ~/Library/Caches -iname "update.log" -print
```

Remove only TMRW update-state files/folders. Do not delete the full user profile unless a clean profile test is intended.

## Expected successful result

A clean install from the DMG should show:

```text
Version: 1.0.20260629
BuildID: 20260629064709
```

It should not immediately show:

```text
Restart to Update TMRW
```
