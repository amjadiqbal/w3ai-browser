━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  W3Ai Change Tree  ·  2026-04-12  20:58  ·  branch: w3ai/develop
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

◉  2026-04-12  [960876f5]  docs(changelly): add comprehensive development & setup guides
   7 files changed  +1659  −12
   │
   ├── browser/
   │   └── extensions/
   │       └── changelly-exchange/
   │           ├── backend/
   │           │   └── src/
   │           │       └── clients/
   │           │           └── [M]  changelly-exchange.ts   +1 −1
   │           ├── [A]  .startup-guide.sh   +51
   │           ├── [A]  DEVELOPMENT.md   +671
   │           ├── [A]  QUICK-START.md   +353
   │           ├── [A]  README.md   +332
   │           └── [A]  setup.sh   +205
   └── tools/
       └── changelog/
           └── [M]  CHANGE_TREE.md   +46 −11

──────────────────────────────────────────

◉  2026-04-12  [6e52abdc]  fix: align extension manifest (MV2) and proxy API contracts; add comprehens…
   22 files changed  +564  −155
   │
   ├── browser/
   │   └── extensions/
   │       └── changelly-exchange/
   │           ├── backend/
   │           │   ├── scripts/
   │           │   │   └── [A]  smoke-all-endpoints.sh   +55
   │           │   ├── src/
   │           │   │   ├── routes/
   │           │   │   │   ├── [M]  assets.ts   +1 −1
   │           │   │   │   └── [M]  swap.ts   +27 −18
   │           │   │   ├── tests/
   │           │   │   │   ├── routes/
   │           │   │   │   │   └── [A]  all-endpoints.test.ts   +174
   │           │   │   │   ├── security/
   │           │   │   │   │   └── [M]  signer.test.ts   +1 −1
   │           │   │   │   └── [A]  jest.setup.ts   +3
   │           │   │   └── [M]  index.ts   +1 −1
   │           │   ├── [A]  .gitignore   +5
   │           │   ├── [A]  README.md   +46
   │           │   └── [M]  jest.config.json   +1
   │           ├── src/
   │           │   ├── popup/
   │           │   │   └── screens/
   │           │   │       └── [M]  SettingsScreen.tsx   +1 −1
   │           │   ├── services/
   │           │   │   └── [M]  proxy-client.ts   +61 −16
   │           │   ├── tests/
   │           │   │   ├── [M]  AppStore.test.ts   +2
   │           │   │   ├── [M]  jest.setup.ts   +6 −4
   │           │   │   └── [M]  proxy-client.test.ts   +15 −14
   │           │   └── [A]  globals.d.ts   +1
   │           ├── [A]  .gitignore   +11
   │           ├── [M]  jar.mn   +9 −14
   │           ├── [M]  manifest.json   +10 −18
   │           ├── [M]  package.json   +2 −2
   │           └── [M]  tsconfig.json   +8 −6
   └── tools/
       └── changelog/
           └── [M]  CHANGE_TREE.md   +124 −59

──────────────────────────────────────────

◉  2026-04-12  [d0462024]  feat(extension): add production-ready changelly-exchange system add-on
   58 files changed  +4765
   │
   └── browser/
       └── extensions/
           ├── changelly-exchange/
           │   ├── backend/
           │   │   ├── src/
           │   │   │   ├── clients/
           │   │   │   │   ├── [A]  changelly-defi.ts   +52
           │   │   │   │   └── [A]  changelly-exchange.ts   +74
           │   │   │   ├── middleware/
           │   │   │   │   └── [A]  error-handler.ts   +27
           │   │   │   ├── routes/
           │   │   │   │   ├── [A]  assets.ts   +17
           │   │   │   │   ├── [A]  config.ts   +14
           │   │   │   │   ├── [A]  defi.ts   +44
           │   │   │   │   ├── [A]  history.ts   +16
           │   │   │   │   ├── [A]  pairs.ts   +24
           │   │   │   │   ├── [A]  quote.ts   +29
           │   │   │   │   └── [A]  swap.ts   +70
           │   │   │   ├── security/
           │   │   │   │   └── [A]  changelly-signer.ts   +18
           │   │   │   ├── tests/
           │   │   │   │   ├── routes/
           │   │   │   │   │   ├── [A]  quote.test.ts   +70
           │   │   │   │   │   └── [A]  swap.test.ts   +85
           │   │   │   │   └── security/
           │   │   │   │       └── [A]  signer.test.ts   +31
           │   │   │   ├── [A]  env.ts   +25
           │   │   │   └── [A]  index.ts   +81
           │   │   ├── [A]  .env.example   +43
           │   │   ├── [A]  jest.config.json   +7
           │   │   ├── [A]  package.json   +39
           │   │   └── [A]  tsconfig.json   +21
           │   ├── popup/
           │   │   └── [A]  index.html   +17
           │   ├── src/
           │   │   ├── background/
           │   │   │   └── [A]  index.ts   +289
           │   │   ├── config/
           │   │   │   └── [A]  env.ts   +52
           │   │   ├── popup/
           │   │   │   ├── components/
           │   │   │   │   ├── [A]  CopyButton.tsx   +27
           │   │   │   │   ├── [A]  FeeBreakdownRow.tsx   +18
           │   │   │   │   ├── [A]  MaintenanceBanner.tsx   +13
           │   │   │   │   ├── [A]  QuoteCountdown.tsx   +49
           │   │   │   │   ├── [A]  Skeleton.tsx   +24
           │   │   │   │   └── [A]  StatusChip.tsx   +44
           │   │   │   ├── screens/
           │   │   │   │   ├── [A]  ErrorScreen.tsx   +26
           │   │   │   │   ├── [A]  HistoryScreen.tsx   +75
           │   │   │   │   ├── [A]  OnboardingScreen.tsx   +99
           │   │   │   │   ├── [A]  PendingScreen.tsx   +157
           │   │   │   │   ├── [A]  ReceiptScreen.tsx   +50
           │   │   │   │   ├── [A]  ReviewScreen.tsx   +220
           │   │   │   │   ├── [A]  SettingsScreen.tsx   +78
           │   │   │   │   ├── [A]  SwapScreen.tsx   +236
           │   │   │   │   ├── [A]  TokenPickerScreen.tsx   +148
           │   │   │   │   └── [A]  TransactionDetailScreen.tsx   +69
           │   │   │   ├── state/
           │   │   │   │   └── [A]  AppStore.tsx   +212
           │   │   │   ├── styles/
           │   │   │   │   └── [A]  globals.css   +564
           │   │   │   ├── [A]  App.tsx   +99
           │   │   │   ├── [A]  index.tsx   +18
           │   │   │   └── [A]  messaging.ts   +22
           │   │   ├── services/
           │   │   │   └── [A]  proxy-client.ts   +223
           │   │   ├── shared/
           │   │   │   └── [A]  types.ts   +333
           │   │   └── tests/
           │   │       ├── [A]  AppStore.test.ts   +64
           │   │       ├── [A]  jest.setup.ts   +21
           │   │       └── [A]  proxy-client.test.ts   +88
           │   ├── [A]  DESIGN.md   +389
           │   ├── [A]  jar.mn   +15
           │   ├── [A]  jest.config.json   +12
           │   ├── [A]  manifest.json   +59
           │   ├── [A]  moz.build   +13
           │   ├── [A]  package.json   +39
           │   ├── [A]  tsconfig.json   +26
           │   └── [A]  webpack.config.js   +89
           └── [M]  moz.build   +1

──────────────────────────────────────────

◉  2026-04-09  [45ead852]  feat(release): add android emulator and ios simulator workflows
   7 files changed  +1248  −155
   │
   └── tools/
       └── release/
           ├── android/
           │   ├── [M]  build.sh   +273 −61
           │   └── [A]  run-emulator.sh   +269
           ├── ios/
           │   ├── [M]  build.sh   +189 −68
           │   └── [A]  run-simulator.sh   +239
           ├── [M]  DEPLOYMENT.md   +115 −25
           ├── [M]  README.md   +144
           └── [M]  release-build.sh   +19 −1

──────────────────────────────────────────

◉  2026-04-09  [593df89c]  fix(release-build): correct ROOT_DIR path for release directory
   1 file changed  +1  −1
   │
   └── tools/
       └── release/
           └── [M]  release-build.sh   +1 −1

──────────────────────────────────────────

◉  2026-04-09  [5d1ea1d7]  chore(changelog): update change tree
   1 file changed  +25  −11
   │
   └── tools/
       └── changelog/
           └── [M]  CHANGE_TREE.md   +25 −11

──────────────────────────────────────────

◉  2026-04-09  [c33d65f2]  fix(branding): correct ROOT_DIR detection in mach-run-branded.sh
   9 files changed  +1012  −19
   │
   ├── browser/
   │   └── themes/
   │       └── shared/
   │           └── [M]  w3ai-theme.css   +2 −1
   └── tools/
       ├── changelog/
       │   └── [M]  CHANGE_TREE.md   +15 −18
       └── release/
           ├── android/
           │   └── [A]  build.sh   +131
           ├── ios/
           │   └── [A]  build.sh   +149
           ├── macos/
           │   ├── [A]  build-dev.sh   +104
           │   ├── [A]  build-prod.sh   +181
           │   └── [A]  mach-run-branded.sh   +102
           ├── [M]  DEPLOYMENT.md   +239
           └── [A]  release-build.sh   +89

──────────────────────────────────────────

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
