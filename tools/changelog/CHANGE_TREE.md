━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  W3Ai Change Tree  ·  2026-04-07  18:34  ·  branch: w3ai/develop
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

◉  2026-04-07  [6cc363fe]  feat(changelog): add graphical change-tree generator and enforce in Copilot…
   4 files changed  +459
   │
   ├── .github/
   │   ├── instructions/
   │   │   └── [M]  release-operations.instructions.md   +9
   │   └── [M]  copilot-instructions.md   +12
   └── tools/
       └── changelog/
           ├── [A]  CHANGE_TREE.md   +150
           └── [A]  change-tree.py   +288

──────────────────────────────────────────

◉  2026-04-07  [45aac362]  fix(sidebar): revert content area order and wire show/hide animation
   3 files changed  +11  −15
   │
   └── browser/
       ├── base/
       │   └── content/
       │       └── [M]  browser-box.inc.xhtml   +4 −4
       ├── components/
       │   └── sidebar/
       │       └── [M]  browser-sidebar.js   +6
       └── themes/
           └── shared/
               └── [M]  sidebar.css   +1 −11

──────────────────────────────────────────

◉  2026-04-07  [8ca84bcc]  feat(sidebar): reorder content area, smooth sidebar transitions, and enforc…
   5 files changed  +49  −5
   │
   ├── .github/
   │   ├── instructions/
   │   │   └── [M]  release-operations.instructions.md   +9
   │   └── [M]  copilot-instructions.md   +12
   └── browser/
       ├── base/
       │   └── content/
       │       └── [M]  browser-box.inc.xhtml   +4 −4
       ├── components/
       │   └── sidebar/
       │       └── [M]  sidebar-main.css   +13
       └── themes/
           └── shared/
               └── [M]  sidebar.css   +11 −1

──────────────────────────────────────────

◉  2026-04-07  [ee621f34]  W3Ai: add default release build command and notarization scripts for macOS
   7 files changed  +250  −11
   │
   ├── .github/
   │   ├── instructions/
   │   │   └── [M]  release-operations.instructions.md   +5
   │   └── [M]  copilot-instructions.md   +8
   └── tools/
       └── release/
           ├── macos/
           │   ├── [A]  release-build-notarize.sh   +81
           │   └── [A]  sign-and-notarize-dev.sh   +139
           ├── [M]  CODING.md   +1
           ├── [M]  DEPLOYMENT.md   +15 −10
           └── [M]  README.md   +1 −1

──────────────────────────────────────────

◉  2026-04-06  [209e8d4a]  enhance Copilot instructions with detailed preflight workflow and automatic…
   2 files changed  +63
   │
   └── .github/
       ├── instructions/
       │   └── [M]  release-operations.instructions.md   +20
       └── [M]  copilot-instructions.md   +43

──────────────────────────────────────────

◉  2026-04-06  [2909de15]  W3Ai: add comprehensive Copilot instructions for branching, release, and de…
   2 files changed  +85
   │
   └── .github/
       ├── instructions/
       │   └── [A]  release-operations.instructions.md   +32
       └── [A]  copilot-instructions.md   +53

──────────────────────────────────────────

◉  2026-04-06  [f81253bf]  docs: comprehensive release + deployment guide (4000+ lines)
   8 files changed  +4006
   │
   └── tools/
       └── release/
           ├── [A]  BRANCH_STRATEGY.md   +253
           ├── [A]  CODING.md   +393
           ├── [A]  DEPLOYMENT.md   +772
           ├── [A]  MERGE_STRATEGY.md   +427
           ├── [A]  README.md   +528
           ├── [A]  SERVER_SETUP.md   +692
           ├── [A]  UPDATE_MANIFESTS.md   +484
           └── [A]  VERSIONING.md   +457

──────────────────────────────────────────

◉  2026-04-05  [d5f4cd94]  W3Ai: update theme styles for improved visual consistency and accessibility
   4 files changed  +281  −331
   │
   └── browser/
       ├── components/
       │   └── sidebar/
       │       └── [M]  sidebar-main.css   −5
       └── themes/
           ├── osx/
           │   └── [M]  browser.css   +1 −14
           └── shared/
               ├── tabbrowser/
               │   └── [M]  tabs.css   +3 −4
               └── [M]  w3ai-theme.css   +277 −308

──────────────────────────────────────────

◉  2026-04-03  [89552435]  W3Ai: structural layout refactor — sidebar shell + main panel, no CSS hacks
   4 files changed  +112  −120
   │
   └── browser/
       ├── base/
       │   └── content/
       │       ├── [M]  browser-box.inc.xhtml   +73 −30
       │       ├── [M]  browser.xhtml   −2
       │       └── [M]  navigator-toolbox.inc.xhtml   −13
       └── themes/
           └── shared/
               └── [M]  w3ai-theme.css   +39 −75

──────────────────────────────────────────

◉  2026-04-02  [003243ff]  W3Ai: fix nav arrows to right-edge of sidebar; push bookmarks/notification …
   1 file changed  +17  −5
   │
   └── browser/
       └── themes/
           └── shared/
               └── [M]  w3ai-theme.css   +17 −5
