# WebKit Migration Next Steps

## Immediate next step

Perform a source audit of the current Gecko browser and write the inventory into `FEATURE_INVENTORY.md`.

## Audit checklist

```text
1. Find all TMRW branding assets.
2. Find all customized browser UI files.
3. Find toolbar and address bar customizations.
4. Find menu customizations.
5. Find download UI behavior.
6. Find history UI behavior.
7. Find bookmarks UI behavior.
8. Find settings/preferences customizations.
9. Find new tab page customizations.
10. Find backend/API dependencies.
11. Find update/release customizations that should not move to the WebKit app.
```

## MVP feature list to confirm

```text
Native macOS app shell
WKWebView page loading
Address bar URL/search
Back/forward/reload
Tabs
Basic history
Basic downloads
Basic bookmarks
Settings window
TMRW branding
App Store signing/sandboxing
```

## Questions to answer during audit

```text
What exact UI from current TMRW must be copied first?
Does the browser have a custom new tab page?
Does it have login/account features?
Does it depend on W3Ai backend APIs?
Does it need browser extensions?
Does it need wallet/web3 functionality?
Does it need sync across devices?
Which features are required for App Store MVP?
```

## Do not do yet

```text
Do not try to port Gecko code directly.
Do not copy Firefox updater logic.
Do not build profile import before MVP browser shell works.
Do not start App Store submission before sandbox and privacy review.
```
