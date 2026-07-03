# TMRW macOS TestFlight packaging notes

## Current target

```text
Version: 1.2.1
Branch: fix/testflight-1-2-1-loading
Base: w3ai/pre-develop
```

## Root cause summary

The TestFlight error for build 1.2.0 points at the nested Gecko content-process app:

```text
TMRW.app/Contents/MacOS/plugin-container.app
```

Transporter reported that this nested executable has an application identifier in its signature but the nested bundle does not contain a matching embedded provisioning profile.

That is a packaging/signing issue, not a normal website issue.

Gecko uses `plugin-container.app` for web/content processes. If the nested app cannot launch correctly in the sandbox/TestFlight environment, the browser chrome can open but page content can fail to load.

The provided runtime logs match that class of failure:

```text
remoteTab is null
messageManager is null
currentWindowGlobal is null
getLoadContextContentPrincipal failure
```

These errors usually happen after the browser UI exists but the content browser/process is not correctly created.

## Changes in this branch

```text
browser/config/version.txt -> 1.2.1
browser/config/version_display.txt -> 1.2.1
build/macos/testflight/TMRW.entitlements
build/macos/testflight/plugin-container.entitlements
scripts/package-testflight-macos.sh
```

## Required provisioning profiles

You need two Mac App Store provisioning profiles from Apple Developer:

```text
1. Main app profile for TMRW.app bundle id
2. Nested app profile for plugin-container.app bundle id
```

The nested profile must match the bundle identifier printed by:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  /path/to/TMRW.app/Contents/MacOS/plugin-container.app/Contents/Info.plist
```

If the nested bundle id does not exist in Apple Developer, create an App ID for it and create a Mac App Store provisioning profile for it.

## Package command

After building TMRW.app, run:

```bash
chmod +x scripts/package-testflight-macos.sh

APP_PATH="/path/to/TMRW.app" \
OUT_DIR="$PWD/dist-testflight" \
VERSION="1.2.1" \
APP_SIGN_IDENTITY="3rd Party Mac Developer Application: Plato Technologies inc. (TEAMID)" \
INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Plato Technologies inc. (TEAMID)" \
MAIN_PROVISION_PROFILE="/path/to/TMRW-main.provisionprofile" \
PLUGIN_CONTAINER_PROVISION_PROFILE="/path/to/TMRW-plugin-container.provisionprofile" \
scripts/package-testflight-macos.sh
```

The output will be:

```text
dist-testflight/TMRW-1.2.1-TestFlight.pkg
```

Upload that pkg using Transporter.

## Local verification

Before upload, verify:

```bash
codesign --verify --deep --strict --verbose=2 /path/to/TMRW.app
codesign -dv --verbose=4 /path/to/TMRW.app 2>&1 | grep -E 'Identifier|TeamIdentifier'
codesign -dv --verbose=4 /path/to/TMRW.app/Contents/MacOS/plugin-container.app 2>&1 | grep -E 'Identifier|TeamIdentifier'

ls -la /path/to/TMRW.app/Contents/embedded.provisionprofile
ls -la /path/to/TMRW.app/Contents/MacOS/plugin-container.app/Contents/embedded.provisionprofile

pkgutil --check-signature dist-testflight/TMRW-1.2.1-TestFlight.pkg
```

## Runtime verification

Install the pkg and launch from `/Applications/TMRW.app`, not from an old Dock entry.

Then check:

```text
About dialog shows 1.2.1, not 1.0.0
A website loads successfully
No immediate content-process related errors appear in Console
```

## If websites still do not load

Check whether `plugin-container.app` actually launches:

```bash
ps aux | grep -i plugin-container | grep -v grep
```

If it does not launch, inspect signing and sandbox logs:

```bash
log stream --predicate 'process CONTAINS "TMRW" OR process CONTAINS "plugin-container"' --style compact
```

The next likely fixes would be:

```text
1. Add required sandbox entitlements to plugin-container.app.
2. Ensure nested profile capabilities match the entitlements.
3. Ensure the nested app bundle identifier matches the provisioning profile.
4. Ensure the parent app and nested app use the same Team ID.
```
