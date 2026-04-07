# Where to Write Code - W3Ai Browser Development

This document explains where to write code for different types of changes.

## Code Organization

```
W3Ai Browser Repository Structure
├── browser/                    # Firefox UI (frontend, toolbar, menus)
├── toolkit/                    # Cross-platform UI components
├── dom/                        # DOM implementation
├── js/                         # JavaScript engine (SpiderMonkey)
├── gfx/                        # Graphics and rendering
├── layout/                     # Layout engine
├── devtools/                   # Developer tools
├── tools/release/             # **W3AI RELEASE & DEPLOYMENT TOOLS**
│   ├── BRANCH_STRATEGY.md
│   ├── CODING.md             # (this file)
│   ├── MERGE_STRATEGY.md
│   ├── VERSIONING.md
│   ├── TESTING.md
│   ├── DEPLOYMENT.md
│   └── UPDATE_MANIFESTS.md
└── media/                      # Media and video components
```

## Types of Code Changes and Where to Write Them

### 1. **UI/Theme Changes** 🎨
**Directory**: `browser/themes/shared/` and `toolkit/themes/`

```
browser/themes/shared/
├── w3ai-theme.css          ← W3Ai color tokens & palette
├── preferences/
├── privatebrowsing/
└── ...

toolkit/themes/shared/
├── in-content/
├── design-system/
└── ...
```

**Example: Change color scheme**
```bash
# 1. Edit the token file
vim browser/themes/shared/w3ai-theme.css

# Add/modify color variables:
--color-accent-primary: hsl(82, 85%, 55%);    # Neon green
--color-accent-secondary: hsl(220, 90%, 60%); # Bright blue
--background-color-canvas: hsl(220, 20%, 4%); # Deep dark

# 2. Reference in component CSS
vim browser/themes/shared/preferences/preferences.css

# Use the token:
.sidebar-item {
  color: var(--color-accent-primary);
  background: var(--background-color-canvas);
}

# 3. Test immediately
./mach build
./mach run --headless about:preferences --screenshot /tmp/test.png

# 4. Git workflow
git checkout -b feature/update-theme-tokens
git add browser/themes/
git commit -m "theme: update W3Ai color tokens for better contrast"
git push -u origin feature/update-theme-tokens
# → Create PR
```

---

### 2. **Browser UI Changes (Toolbar, Menus)** 🛠️
**Directory**: `browser/components/` and `browser/base/content/`

```
browser/components/
├── preferences/      # Settings dialog
├── aboutlogins/      # Password manager
├── protections/      # Privacy protections panel
├── newtab/          # New tab page
└── ...

browser/base/content/
├── browser.xhtml     # Main window layout
├── browser.js        # Window scripting
└── ...
```

**Example: Add button to toolbar**
```bash
# 1. Edit the layout file
vim browser/base/content/browser.xhtml

# Add button (XUL element):
<toolbarbutton
  id="w3ai-custom-button"
  class="toolbarbutton-1"
  data-l10n-id="w3ai-action-button"
  oncommand="W3AIActions.handleCustomAction()"
/>

# 2. Add localization strings
vim browser/locales/en-US/browser/customButtons.ftl

w3ai-action-button = W3Ai Action
w3ai-action-button.tooltip = Perform custom W3Ai action

# 3. Add JavaScript logic
vim browser/base/content/browser.js

const W3AIActions = {
  handleCustomAction() {
    // Your logic here
    console.log("W3Ai action triggered");
  }
};

# 4. Test
./mach build
./mach run  # Manual testing

# 5. Git workflow
git checkout -b feature/add-custom-toolbar-button
git add browser/
git commit -m "feat(ui): add custom W3Ai action button to toolbar"
git push -u origin feature/add-custom-toolbar-button
```

---

### 3. **Preference/Configuration Changes** ⚙️
**Files**:
- `browser/app/profile/firefox.js` (default prefs)
- `browser/branding/w3ai/pref/firefox-branding.js` (W3Ai-specific prefs)

```bash
# 1. Edit preference file
vim browser/app/profile/firefox.js

# Add or modify pref:
pref("browser.w3ai.enableAdvancedsearch", true);
pref("browser.w3ai.defaultEngine", "Google");
pref("browser.w3ai.checkUpdateInterval", 3600); // seconds

# 2. Document what the pref does
// Enable W3Ai advanced search features
// Type: boolean | default: true

# 3. Test preference is applied
./mach build
./mach run  # Check in about:config

# 4. Git workflow
git checkout -b feature/add-w3ai-prefs
git add browser/app/profile/ browser/branding/
git commit -m "prefs: add W3Ai-specific configuration preferences"
git push -u origin feature/add-w3ai-prefs
```

---

### 4. **New Feature - Extensions/Add-ons** 🧩
**Directory**: `browser/extensions/`

```bash
# 1. Create extension directory
mkdir -p browser/extensions/w3ai-myfeature/

# 2. Create structure
browser/extensions/w3ai-myfeature/
├── manifest.json          # Add-on metadata
├── components/
│   └── my-component.js
├── content/
│   └── my-script.js
└── moz.build

# 3. Register in build system
echo 'DIRS += ["w3ai-myfeature"]' >> browser/extensions/moz.build

# 4. Test
./mach build
./mach run

# 5. Git workflow
git checkout -b feature/add-myfeature-extension
git add browser/extensions/
git commit -m "feat: add W3Ai my-feature extension"
git push -u origin feature/add-myfeature-extension
```

---

### 5. **DOM/JavaScript Engine Changes** 🔧
**Directories**: `dom/`, `js/` (requires C++/Rust)

```bash
# For DOM changes:
# vim dom/base/Element.cpp
# vim dom/base/Element.h

# For SpiderMonkey changes:
# vim js/src/vm/JSContext.cpp
# vim js/src/vm/JSContext.h

# Build test
./mach build
./mach test js/

# Git workflow
git checkout -b feature/add-dom-feature
git add dom/ js/
git commit -m "feat(dom): add new DOM API for W3Ai features"
git push -u origin feature/add-dom-feature
```

---

### 6. **Testing Changes** 🧪
**Directory**: `browser/base/content/test/` and `testing/`

```
browser/base/content/test/
├── browser_test1.js       # Browser UI tests
├── general/
└── ...

testing/mochitest/        # Test framework
```

**Example: Add test for new feature**
```bash
# 1. Create test file
vim browser/base/content/test/test_w3ai_feature.js

// Test code
add_task(async function test_w3ai_feature() {
  // Setup
  let tab = await BrowserTestUtils.openNewForegroundTab(gBrowser);
  
  // Test
  ok(gBrowser, "Browser exists");
  
  // Cleanup
  BrowserTestUtils.removeTab(tab);
});

# 2. Add to test manifest
vim browser/base/content/test/mochitest.ini

[test_w3ai_feature.js]

# 3. Run tests
./mach test browser/base/content/test/test_w3ai_feature.js

# 4. Git workflow
git checkout -b feature/add-w3ai-tests
git add browser/base/content/test/
git commit -m "test: add unit tests for W3Ai feature"
git push -u origin feature/add-w3ai-tests
```

---

### 7. **Build System Changes** 🏗️
**Files**: `moz.build`, `moz.configure`

```bash
# Add new component to build
vim browser/components/w3ai/moz.build

DIRS += [
  'mycomponent',
]

XPIDL_SOURCES += [
  'interfaces/nsIMyComponent.idl',
]

JS_PREFERENCE_PP_FILES += [
  'prefs.js',
]

# Git workflow
git checkout -b feature/update-build-system
git add moz.build moz.configure
git commit -m "build: register W3Ai components in build system"
git push -u origin feature/update-build-system
```

---

### 8. **Release & Deployment Changes** 📦
**Directory**: `tools/release/` (W3AI ONLY)

```
tools/release/
├── BRANCH_STRATEGY.md          # Branch workflow
├── CODING.md                   # This file
├── MERGE_STRATEGY.md           # How to merge to production
├── VERSIONING.md               # Version numbering
├── TESTING.md                  # Pre-release testing
├── DEPLOYMENT.md               # Production deployment
├── UPDATE_MANIFESTS.md         # Firefox update XML
├── branching/
│   └── setup-branch-strategy.sh
├── macos/
│   ├── release-build-notarize.sh
│   └── sign-and-notarize-dev.sh
└── update-host/
    ├── channel-map.json
    └── updates/
        └── {dev,rc,prod}/

# Git workflow
git checkout -b feature/improve-deployment
git add tools/release/
git commit -m "docs(release): document deployment procedures
- Added checklist for pre-release validation
- Clarified update manifest requirements
- Updated notarization workflow"
git push -u origin feature/improve-deployment
```

---

## Development Workflow Checklist

When writing code, follow these steps:

- [ ] Create feature branch from `w3ai/develop`
- [ ] Make code changes in appropriate directory
- [ ] Follow existing code style (Firefox style guidelines)
- [ ] Add comments for non-obvious logic
- [ ] Write/update tests
- [ ] Test locally: `./mach build && ./mach test --auto`
- [ ] Test UI in browser: `./mach run`
- [ ] Take screenshots for validation
- [ ] Commit with clear message (see MERGE_STRATEGY.md)
- [ ] Push to GitHub
- [ ] Open PR with description and test evidence
- [ ] Address reviewer feedback
- [ ] Get approval
- [ ] Merge to `w3ai/develop` via GitHub UI
- [ ] Verify merged commit in history
- [ ] Delete feature branch

---

## Common Tasks and File Locations

| Task | File(s) | Command |
|------|---------|---------|
| Change colors | `browser/themes/shared/w3ai-theme.css` | `./mach build` |
| Add toolbar button | `browser/base/content/browser.xhtml` | `./mach run` |
| Add preference | `browser/app/profile/firefox.js` | `./mach build` |
| Add localization | `browser/locales/en-US/browser/` | `./mach build` |
| Write test | `browser/base/content/test/test_*.js` | `./mach test` |
| Update build | `moz.build` | `./mach build` |
| Release workflow | `tools/release/DEPLOYMENT.md` | See deployment guide |

---

## Need Help Finding Files?

Use searchfox to find where code lives:
```bash
# Find file by identifier (C++/Rust)
searchfox-cli --define "MyClass" --cpp

# Find file by text search (restricted to path)
searchfox-cli --path browser/base --q "handleButtonClick"

# Find JavaScript usage
searchfox-cli --id gBrowser -l 50 --js
```

Or use local tools:
```bash
# Find CSS files with specific class
grep -r "my-class-name" browser/themes/ toolkit/themes/

# Find JavaScript file
find browser -name "*action*" -type f

# Find references to symbol
rg "handleCustomAction" browser/base/content/
```
