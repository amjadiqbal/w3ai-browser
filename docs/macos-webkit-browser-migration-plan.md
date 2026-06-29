# TMRW macOS WebKit Browser Migration Plan

## Goal

Build a new Mac App Store eligible TMRW Browser using Apple's WebKit stack while preserving the product experience already designed in the current Gecko browser.

This is not a direct engine port. Gecko, XUL, XPCOM, Firefox updater internals, and Mozilla profile internals should not become the base of the new app. The new app should be a native macOS browser using Swift, AppKit or SwiftUI, and WKWebView.

## Platform rule

For normal App Store submission, the browser should use WKWebView/WebKit. The Gecko build can remain the direct-download version, while the WebKit app becomes the App Store version.

## Foundation modules

The new app should be built around these modules:

```text
TMRWBrowserApp
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

### AppShell

Boots the app and owns shared services such as settings, history, bookmarks, downloads, profile paths, and active windows.

### BrowserWindow

Owns the main browser interface: toolbar, address bar, tabs, sidebar, web view area, status area, and panels.

### TabManager

Owns tab state: id, url, title, favicon, loading state, progress, back/forward availability, pinned state, private state, and WKWebView session.

### WebViewHost

Wraps WKWebView. Handles navigation, page title, loading progress, JavaScript dialogs, permission prompts, external URLs, downloads, and navigation errors.

### Stores

History, bookmarks, downloads, settings, and profile state should be owned by TMRW, not copied from Firefox internals. Use SQLite or Core Data.

## Technology stack

```text
Language: Swift
UI: SwiftUI with AppKit where needed
Web engine: WKWebView
Storage: SQLite or Core Data
Downloads: WKDownload and URLSessionDownloadTask
Menus: NSMenu or SwiftUI Commands
Build: Xcode
Signing: Apple Developer signing with sandbox entitlements
Distribution: TestFlight, then Mac App Store
```

## Migration milestones

### Milestone 0: Current browser audit

Create a full inventory of the existing Gecko browser UI and features.

Deliverables:

```text
docs/migration-memory/FEATURE_INVENTORY.md
docs/migration-memory/MODULE_MAP.md
docs/migration-memory/DECISIONS.md
```

Estimated time: 6 to 12 focused hours.

### Milestone 1: Native WebKit skeleton

Create an Xcode macOS app with a TMRW branded browser window and one WKWebView.

Deliverables:

```text
Xcode project
AppShell
BrowserWindow
Address bar
Basic navigation
Back, forward, reload
```

Estimated time: 8 to 16 focused hours.

### Milestone 2: Tabs and browser chrome

Add real browser behavior.

Deliverables:

```text
TabManager
Tab strip
New tab
Close tab
Loading progress
URL/search routing
Page title updates
```

Estimated time: 16 to 32 hours.

### Milestone 3: History, downloads, bookmarks

Replace Firefox internal services with native TMRW services.

Deliverables:

```text
HistoryStore
DownloadManager
BookmarkStore
Download UI
History UI
Bookmark UI
```

Estimated time: 24 to 48 hours.

### Milestone 4: Settings and privacy

Add settings and App Store safe permission behavior.

Deliverables:

```text
Settings window
Search engine settings
Download location settings
Website permissions
Clear browsing data
Privacy notes
```

Estimated time: 16 to 32 hours.

### Milestone 5: Visual replication

Match the current TMRW browser design.

Deliverables:

```text
Toolbar layout
Sidebar layout
New tab design
Menus
About screen
Icons
Theme tokens
```

Estimated time: 24 to 60 hours.

### Milestone 6: App Store pipeline

Prepare the build for TestFlight and App Store review.

Deliverables:

```text
Bundle ID
Signing
Sandbox entitlements
App icons
Privacy manifest
Archive/export setup
App Review notes
QA checklist
```

Estimated time: 8 to 20 hours.

## Time expectation

```text
8 to 12 hours: enough for architecture, documentation, source audit start, and a basic skeleton plan.
2 to 4 weeks: realistic for a usable WebKit MVP browser.
4 to 8+ weeks: realistic for a polished App Store ready browser matching the current TMRW design.
```

## Session memory system

Every work session must update files in:

```text
docs/migration-memory/
```

Required files:

```text
STATUS.md
DECISIONS.md
FEATURE_INVENTORY.md
MODULE_MAP.md
NEXT_STEPS.md
RISKS.md
```

Before working, read `STATUS.md` and `NEXT_STEPS.md`. After working, update both files.

## First MVP target

The first working version should do only this:

```text
Open the app
Show a TMRW branded browser window
Load a default homepage
Navigate from the address bar
Support back, forward, reload
Open and close tabs
Record basic history
Download files to the Downloads folder
```

That is the foundation. Everything else connects to it.
