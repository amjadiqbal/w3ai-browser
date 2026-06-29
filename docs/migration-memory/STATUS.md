# WebKit Migration Status

## Branch

```text
feature/macos-webkit-browser-plan
```

## Current objective

Design a native macOS WebKit version of TMRW Browser that can be prepared for Mac App Store distribution.

## Current phase

```text
Phase 0: planning and source audit preparation
```

## What has been created

```text
docs/macos-webkit-browser-migration-plan.md
docs/migration-memory/STATUS.md
```

## Current understanding

The current TMRW browser is based on Firefox/Gecko. The App Store version should not depend on Gecko, Firefox updater internals, XUL, XPCOM, or Mozilla binary metadata patching. The App Store version should be a new native macOS app using WKWebView/WebKit.

## Main architecture decision

Use a native app foundation:

```text
AppShell
BrowserWindow
TabManager
WebViewHost
NavigationStore
HistoryStore
DownloadManager
BookmarkStore
ProfileStore
SettingsStore
```

## Next required work

```text
1. Audit the current Gecko browser UI and custom TMRW files.
2. Create FEATURE_INVENTORY.md.
3. Create MODULE_MAP.md.
4. Decide MVP vs Phase 2 features.
5. Create an Xcode project skeleton in a separate folder or repo.
```

## Notes for future sessions

Before continuing, read this file and NEXT_STEPS.md if it exists. After working, update STATUS.md with what changed and update NEXT_STEPS.md with the next action list.
