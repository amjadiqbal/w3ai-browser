# W3Ai Browser Release & Deployment Master Guide

**Complete reference for development, release, and deployment workflow**

---

## Quick Start: Where Do I Start?

```
Are you...?

1️⃣ Adding a feature/fixing a bug?
   → Read: BRANCH_STRATEGY.md → CODING.md → MERGE_STRATEGY.md

2️⃣ Preparing a release?
   → Read: VERSIONING.md → DEPLOYMENT.md (Phase 1-3)

3️⃣ Setting up update server?
   → Read: SERVER_SETUP.md → UPDATE_MANIFESTS.md

4️⃣ Deploying to production?
   → Read: DEPLOYMENT.md (Phases 1-6)

5️⃣ Troubleshooting an issue?
   → Read: Respective document's "Troubleshooting" section
```

---

## Document Overview

| Document | Purpose | For |
|----------|---------|-----|
| **BRANCH_STRATEGY.md** | Branch hierarchy and when to use each | All developers |
| **CODING.md** | Where to write code for each type of change | Frontend/backend developers |
| **MERGE_STRATEGY.md** | How to merge code safely through branches | PR reviewers, release manager |
| **VERSIONING.md** | Semantic versioning and tagging strategy | Release manager |
| **UPDATE_MANIFESTS.md** | Firefox update XML file structure | DevOps, release manager |
| **DEPLOYMENT.md** | Step-by-step production deployment | Release manager |
| **SERVER_SETUP.md** | Configure update distribution server | DevOps, sys admin |

---

## Build Command Matrix

Use these commands when you need an artifact you can copy directly from disk.

### macOS

Development DMG, unsigned:

```bash
./tools/release/release-build.sh macos-dev
```

Output:
- `obj-*/dist/*.dmg`

Production DMG, signed but not notarized:

```bash
./tools/release/release-build.sh macos-prod --no-notarize
```

Output:
- `obj-*/dist/*.dmg`

Production DMG, signed and notarized:

```bash
./tools/release/release-build.sh macos-prod --keychain-profile <profile>
```

Or:

```bash
./tools/release/release-build.sh macos-prod --apple-id <apple-id> --team-id <team-id>
```

Output:
- `obj-*/dist/*.dmg`

### Android

Android development APK:

```bash
./tools/release/release-build.sh android --dev
```

Output:
- `mobile/android/fenix/app/build/outputs/apk/debug/*.apk`

Run on Android emulator (build + install + launch):

```bash
./tools/release/android/run-emulator.sh --build
```

Run on a specific AVD with an existing APK:

```bash
./tools/release/android/run-emulator.sh --avd Pixel_6a --apk /absolute/path/to/app-universal-debug.apk
```

Android release APK, unsigned:

```bash
./tools/release/release-build.sh android --prod
```

Output:
- `mobile/android/fenix/app/build/outputs/apk/release/*release*.apk`

Android release APK, signed:

```bash
export W3AI_ANDROID_STORE_PASSWORD='...'
export W3AI_ANDROID_KEY_PASSWORD='...'

./tools/release/release-build.sh android --prod \
        --keystore /absolute/path/to/w3ai-release.keystore \
        --key-alias w3ai-release \
        --store-password-env W3AI_ANDROID_STORE_PASSWORD \
        --key-password-env W3AI_ANDROID_KEY_PASSWORD
```

Signing data you must provide:
- keystore path
- key alias
- keystore password environment variable
- key password environment variable

Output:
- Unsigned APKs: `mobile/android/fenix/app/build/outputs/apk/release/`
- Signed APK: same directory with `-signed.apk`

### iOS

iOS development IPA:

```bash
./tools/release/release-build.sh ios --dev --team-id <team-id>
```

iOS production IPA:

```bash
./tools/release/release-build.sh ios --prod --team-id <team-id>
```

Optional explicit export mode:

```bash
./tools/release/release-build.sh ios --prod --team-id <team-id> --export-method app-store
```

Output:
- archive: `mobile/ios/build/*.xcarchive`
- IPA: `mobile/ios/build/export-*/`

Run on iOS simulator (build + install + launch):

```bash
./tools/release/ios/run-simulator.sh
```

Run on iOS simulator with explicit runtime:

```bash
./tools/release/ios/run-simulator.sh --runtime-id com.apple.CoreSimulator.SimRuntime.iOS-18-5
```

Important:
- iOS uses IPA export via Xcode.
- iOS does not use DMG packaging.
- iOS does not use Apple notarization.
- The in-tree iOS app is `mobile/ios/GeckoTestBrowser`, so mobile branding and bundle naming must be customized in that project if you want W3Ai-specific iOS assets.
- iOS simulator execution requires an installed simulator runtime (`xcrun simctl list runtimes`).

Important for Android and iOS:
- Android builds come from `mobile/android/fenix`.
- iOS builds come from `mobile/ios/GeckoTestBrowser`.
- These mobile targets are separate from the desktop `browser/branding/w3ai` DMG branding flow.

---

## Complete Development Workflow Timeline

### Week 1-2: Feature Development

```
Day 1:  Developer creates feature branch
        git checkout -b feature/new-awesome-feature

Days 2-5: Makes changes, tests locally
          code → ./mach build → ./mach test → ./mach run

Day 6:  Pushes to GitHub and opens PR
        git push -u origin feature/new-awesome-feature

Day 7:  PR reviewed and approved
        Merged to w3ai/develop via GitHub UI

Result: Code is now on w3ai/develop branch, available for next release
```

### Week 3: Feature Freeze & QA

```
Day 1:  Release manager creates release branch
        git checkout -b release/w3ai-151.0.0-dev
        git tag v151.0.0-dev

Day 2:  QA team begins testing
        Report bugs via GitHub Issues

Days 3-6: Critical bugs fixed via hotfix branches
          Only hotfixes merged to release/* branch
          
Result: RC1 or RC2 created with all fixes
```

### Week 4: Production Release

```
Day 1:  All QA approved, no more issues
        Create release tag: v151.0.0
        Merge release/* → production

Days 2-3: Sign and notarize DMG
          Upload to update server
          Create update manifests

Day 4:  Release announced to users
        Users begin receiving updates

Days 5-30: Monitor adoption
           Fix any reported bugs in hotfixes
           
Result: v151.0.0 rolled out to users
        w3ai/develop ready for v152.0.0 development
```

---

## Key Documents by Role

### 👨‍💻 Frontend Developer

Start with:
1. [BRANCH_STRATEGY.md](./BRANCH_STRATEGY.md) - Understanding branches
2. [CODING.md](./CODING.md) - Where to write UI code
3. [MERGE_STRATEGY.md](./MERGE_STRATEGY.md) - How to merge your PR

Example: Adding new theme color
- Edit: `browser/themes/shared/w3ai-theme.css`
- Test: `./mach build && ./mach run --headless about:preferences`
- Screenshot: `/tmp/prefs.png`
- Commit: `feat(theme): add new accent color for better accessibility`
- PR: Request review, address feedback, merge

---

### 🔧 Backend/C++ Developer

Start with:
1. [BRANCH_STRATEGY.md](./BRANCH_STRATEGY.md)
2. [CODING.md](./CODING.md) - Look for dom/, js/, media/ sections
3. [MERGE_STRATEGY.md](./MERGE_STRATEGY.md)

Example: Improving DOM API
- Edit: `dom/base/Element.h`, `dom/base/Element.cpp`
- Test: `./mach build && ./mach test js/`
- Commit: `feat(dom): add new parameter to Element.getData()`
- PR: Describe breaking changes clearly

---

### 🚀 Release Manager

Start with:
1. [VERSIONING.md](./VERSIONING.md) - Understanding version numbers
2. [DEPLOYMENT.md](./DEPLOYMENT.md) - The complete deployment playbook
3. [UPDATE_MANIFESTS.md](./UPDATE_MANIFESTS.md) - Update file structure
4. [SERVER_SETUP.md](./SERVER_SETUP.md) - Server configuration

Checklist before release:
- [ ] Feature freeze date passed
- [ ] All PR reviews complete
- [ ] Tests passing
- [ ] DMG built and signed
- [ ] Update manifests prepared
- [ ] Server ready
- [ ] Team notified

---

### 🖥️ DevOps / System Administrator

Start with:
1. [SERVER_SETUP.md](./SERVER_SETUP.md) - Server configuration (one-time)
2. [UPDATE_MANIFESTS.md](./UPDATE_MANIFESTS.md) - XML file format
3. [DEPLOYMENT.md](./DEPLOYMENT.md) - Phase 4 (Server Deployment)

Tasks:
- [ ] Set up update.w3ai.dev server
- [ ] Configure Nginx with SSL
- [ ] Test manifests and downloads
- [ ] Set up monitoring
- [ ] Monitor server health during releases

---

## Common Scenarios

### Scenario 1: "I found a bug in development"

```bash
# 1. You're on feature branch
git checkout feature/my-feature

# 2. Create fix commit
git add browser/themes/shared/fixed-file.css
git commit -m "fix: correct color value in theme"

# 3. Push and update PR
git push origin feature/my-feature

# 4. PR automatically updates
# Reviewer sees new commits, re-reviews if needed
```

See: [MERGE_STRATEGY.md](./MERGE_STRATEGY.md) - Merge Prevention Strategies

---

### Scenario 2: "Critical bug in production"

```bash
# 1. Create hotfix from production
git checkout production
git pull origin production
git checkout -b hotfix/critical-security-issue

# 2. Fix the issue
# ... edit files ...

# 3. Commit and tag
git commit -am "fix(critical): security XSS vulnerability"
git tag -a v151.0.1 -m "Critical hotfix"

# 4. Merge to production
git checkout production
git merge --no-ff hotfix/critical-security-issue
git push origin production

# 5. Also to w3ai/develop
git checkout w3ai/develop
git merge --no-ff hotfix/critical-security-issue
git push origin w3ai/develop

# 6. Update manifests and deploy
```

See: [MERGE_STRATEGY.md](./MERGE_STRATEGY.md) - Special Case: Hotfix in Production

---

### Scenario 3: "How do I know which version users are running?"

```bash
# Check server logs for update checks
ssh deploy@updates.w3ai.dev <<'SSH'
grep "update.xml" /var/log/nginx/updates.w3ai.dev.access.log | \
  awk '{print $10}' | sort | uniq -c | sort -rn | head -20
SSH

# Parse the User-Agent to extract version:
# User-Agent: Mozilla/5.0 ... Firefox/151.0.0-dev ...
# (Version number is in User-Agent)

# Count downloads by version
grep "W3AiBrowser.*\.dmg" /var/log/nginx/updates.w3ai.dev.access.log | \
  awk '{print $7}' | sort | uniq -c | sort -rn
```

See: [SERVER_SETUP.md](./SERVER_SETUP.md) - Step 3: Monitoring & Maintenance

---

### Scenario 4: "I need to rollback a production release"

```bash
# ⚠️ IMPORTANT: Use only if absolutely necessary

# Option 1: Revert manifest to previous version
cat > /srv/w3ai-updates/prod/macos/update.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    version="151.0.0-rc.1"
    buildID="20240410000000"
  >
    <patch URL="https://updates.w3ai.dev/v151.0.0-rc.1/W3AiBrowser-v151.0.0-rc.1.dmg"
           hashValue="[hash]" size="[size]"/>
  </update>
</updates>
EOF

# Option 2: Create new version with fix
# (preferred - creates audit trail)
git checkout -b hotfix/151.0.2
# ... apply fix ...
git tag v151.0.2
# (Deploy as new version instead of reverting)
```

See: [DEPLOYMENT.md](./DEPLOYMENT.md) - Troubleshooting: Rollback to Previous Version

---

### Scenario 5: "What's the version number format?"

```
MAJOR.MINOR.PATCH-SUFFIX

Examples:
151.0.0-dev          # Development version
151.0.0-rc.1         # Release Candidate 1
151.0.0              # Production release
151.0.1              # Hotfix release
152.0.0-dev          # Next development cycle

Format rules:
- MAJOR: Firefox major version (changes rarely)
- MINOR: Usually 0 (minor version features)
- PATCH: Increments for each bug fix/hotfix
- SUFFIX: -dev, -rc.N, or (none for production)
```

See: [VERSIONING.md](./VERSIONING.md) - Version Numbering

---

### Scenario 6: "How do users get the update?"

```
User runs W3Ai Browser
       ↓ (every 24 hours, checks)
https://updates.w3ai.dev/prod/macos/update.xml
       ↓ (reads XML)
Version 151.0.0 available
       ↓ (downloads if newer)
https://updates.w3ai.dev/v151.0.0/W3AiBrowser-v151.0.0.dmg
       ↓ (verifies hash)
Applies update
       ↓
Restarts browser
       ↓
User sees new version in Help → About
```

Timeline:
- Day 0: Release published
- Days 1-3: Hourly update interval → 30% adoption
- Days 4-7: 12-24 hour intervals → 80% adoption
- Day 30+: Most users updated (98%+)

See: [UPDATE_MANIFESTS.md](./UPDATE_MANIFESTS.md) - How Firefox Updates Work

---

## Branching Overview

```
Production (stable, deployed)
↑ merge --no-ff
│
release/w3ai-151.0.0-dev (testing, QA)
↑ merge --no-ff
│
w3ai/develop (feature integration)
↑ PR merge (squash or rebase)
│
feature/* (individual features)

Also:
hotfix/* ─→ production & w3ai/develop
upstream-sync ─→ w3ai/develop (cherry-pick)
```

Quick commands:
```bash
# Start feature
git checkout -b feature/name
cd /Volumes/Amjad/Plato/W3Ai

# Push and create PR
git push -u origin feature/name

# After PR merged, clean up
git checkout w3ai/develop
git pull origin w3ai/develop
git branch -d feature/name
git push origin --delete feature/name

# Release process (manager only)
git checkout w3ai/develop && git checkout -b release/w3ai-151.0.0-dev
# ... QA testing ...
git checkout production && git merge release/w3ai-151.0.0-dev
git tag -a v151.0.0 -m "Production release"
git push origin production --tags
```

See: [BRANCH_STRATEGY.md](./BRANCH_STRATEGY.md)

---

## Version Tagging Timeline

```
2024-04-01: Development starts
            v151.0.0-dev tag created

2024-04-10: QA begins
            v151.0.0-rc.1 tag (first candidate)
            v151.0.0-rc.2 tag (after QA fixes)

2024-04-15: Approved for production
            v151.0.0 tag (no suffix = production)

2024-04-22: Critical bug found
            v151.0.1 tag (patch version)

2024-05-01: Next development cycle
            v152.0.0-dev tag created
```

Commands:
```bash
git tag -l                    # List all tags
git show v151.0.0             # See tag details
git push origin v151.0.0      # Push single tag
git push origin --tags        # Push all tags
```

See: [VERSIONING.md](./VERSIONING.md)

---

## Essential Commands Reference

### Development
```bash
./mach build              # Rebuild Firefox
./mach test --auto        # Run all tests
./mach run                # Launch browser
./mach format             # Format code
```

### Git
```bash
git checkout -b feature/name              # Create feature
git add . && git commit -m "feat: desc"   # Commit
git push -u origin feature/name           # Push
git checkout w3ai/develop && git pull    # Update main
git merge --no-ff feature/name            # Merge with history
git tag -a v151.0.0 -m "msg"            # Create tag
```

### Testing
```bash
./mach test browser/base/content/test/    # Run specific
./mach run --headless about:preferences   # Headless mode
spctl -a -v browser.app                   # Verify signature
```

---

## File Locations

| What | Where |
|------|-------|
| W3Ai theme colors | `browser/themes/shared/w3ai-theme.css` |
| Preferences | `browser/app/profile/firefox.js` |
| Tests | `browser/base/content/test/` |
| Release docs | `tools/release/` |
| Update manifests | `tools/release/update-host/updates/*/macos/update.xml` |
| Signing scripts | `tools/release/macos/release-build-notarize.sh`, `tools/release/macos/sign-and-notarize-dev.sh` |

---

## Release Checklist

Complete before releasing:

Feature Development:
- [ ] All features coded
- [ ] Code reviewed
- [ ] Tests passing
- [ ] Manual testing done
- [ ] Screenshots captured

Release Prep:
- [ ] Version number chosen
- [ ] Release branch created
- [ ] DMG built
- [ ] App signed & notarized
- [ ] Tag created

QA Testing:
- [ ] QA team tested
- [ ] All about:* pages work
- [ ] Extensions load
- [ ] Theme applies correctly
- [ ] No crash reports

Production Release:
- [ ] Merged to production
- [ ] Tag pushed
- [ ] DMG uploaded to server
- [ ] Manifests updated
- [ ] Update checks working
- [ ] Announcement sent

Post-Release:
- [ ] Monitor adoption
- [ ] Watch for bug reports
- [ ] Hotfix any critical issues
- [ ] Archive old versions

---

## Support Resources

**Questions?**

1. Check the specific document for your task
2. Review troubleshooting section
3. Search GitHub Issues
4. Contact release manager

**Report Issues**: https://github.com/amjadiqbal/w3ai-browser/issues

---

## Document Maintenance

These documents should be updated when:
- [ ] Process changes
- [ ] New tools introduced
- [ ] Procedures streamlined
- [ ] Bugs discovered and fixed

Keep documents in sync:
```bash
git checkout -b docs/update-release-guides
# Edit .md files
git add tools/release/*.md
git commit -m "docs: update release procedures"
git push -u origin docs/update-release-guides
# Create PR for review
```

---

**Last Updated**: 2024-04-06  
**Version**: 1.0  
**Status**: ✅ Production Ready

Next steps: Follow BRANCH_STRATEGY or DEPLOYMENT based on your role.
