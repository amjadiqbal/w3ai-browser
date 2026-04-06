# Versioning & Tagging Strategy

This document explains how to version W3Ai Browser and when to create tags.

## Version Numbering

W3Ai Browser uses **Semantic Versioning** based on Firefox version + custom suffix.

### Version Format

```
MAJOR.MINOR.PATCH-SUFFIX

Examples:
151.0.0-dev          # Development version based on Firefox 151
151.0.0-rc.1         # Release candidate 1
151.0.0              # Production release
151.0.1              # Patch release (hotfix)
152.0.0-beta.1       # Beta for next major version
```

### Version Components

| Component | Meaning | Examples |
|-----------|---------|----------|
| MAJOR | Firefox major version | 151, 152, 153 |
| MINOR | Minor updates (usually 0) | 0 |
| PATCH | Bug fixes, minor updates | 0, 1, 2, 3 |
| SUFFIX | Release status | -dev, -rc.1, -beta.1, (none) |

---

## Version Progression

```
Development Release
└─ 151.0.0-dev (on w3ai/develop branch)
   
Release Candidate
└─ 151.0.0-rc.1 (on release/w3ai-151.0.0-dev branch)
└─ 151.0.0-rc.2 (additional testing rounds)
└─ 151.0.0-rc.N (N rounds of testing)

Production Release
└─ 151.0.0 (on production branch)

Hotfix Releases
└─ 151.0.1 (first hotfix)
└─ 151.0.2 (second hotfix)
└─ 151.0.N (N hotfixes)

Next Version Development
└─ 152.0.0-dev (w3ai/develop)
   └─ 152.0.0-rc.1, 152.0.0-rc.2, ...
   └─ 152.0.0
```

---

## When to Create Tags

### 1. Development Release Tag

**When**: Feature set complete, moving to QA  
**Branch**: w3ai/develop → release/*  
**Tag**: `vMAJOR.MINOR.PATCH-dev`

```bash
git tag -a v151.0.0-dev -m "W3Ai Browser Development Release v151.0.0-dev

### Release Information
- Base: Firefox 151.0.0a1
- Branch: release/w3ai-151.0.0-dev
- Release Date: $(date '+%Y-%m-%d')
- Status: Development (for internal testing)

### Key Features
- W3Ai dark+neon branding system
- Improved theme engine with color tokens
- Enhanced privacy protections
- [add more features]

### Known Issues
- about:newtab in headless mode (upstream Firefox issue)
- [list other known issues]

### Testing
Tested on: macOS 12.6.3+
Build verified with: spctl, codesign, notarytool"

# Verify tag was created
git tag -l v151.0.0-dev
git show v151.0.0-dev
```

### 2. Release Candidate Tag

**When**: First QA round, code ready for testing  
**Branch**: release/w3ai-151.0.0-dev  
**Tag**: `vMAJOR.MINOR.PATCH-rc.N`

```bash
git tag -a v151.0.0-rc.1 -m "W3Ai Browser Release Candidate v151.0.0-rc.1

### Release Candidate #1
- Base: Firefox 151.0.0a1
- Branch: release/w3ai-151.0.0-dev
- Release Date: $(date '+%Y-%m-%d')
- Status: Release Candidate (testing phase)

### Changes from Previous
- Fixed theme color inconsistencies
- Resolved about:preferences crash
- Updated localization strings
- [list changes]

### Testing Focus
Please test:
1. Theme switching and visual consistency
2. All about:* pages (preferences, logins, protections, support)
3. Toolbar and menu functionality
4. Extension compatibility

### If Issues Found
1. Report in: GitHub Issues
2. Include: OS, Firefox version, steps to reproduce
3. Tag: @release-manager

### Expected Release
If no critical issues: Production release in 1 week"

git tag -l v151.0.0-rc.1
git show v151.0.0-rc.1
```

### 3. Production Release Tag

**When**: QA approved, code merged to production  
**Branch**: production  
**Tag**: `vMAJOR.MINOR.PATCH` (no suffix)

```bash
git tag -a v151.0.0 -m "W3Ai Browser Production Release v151.0.0

### Production Release
- Base: Firefox 151.0.0a1
- Branch: production
- Release Date: $(date '+%Y-%m-%d')
- Status: ✅ STABLE (ready for production deployment)

### New Features
- W3Ai brand system with neon accent colors
- Dark mode theme with improved contrast
- Updated privacy dashboard
- [list all features]

### Bug Fixes
- Fixed theme persistence across sessions
- Resolved toolbar button layout issues
- Improved add-on compatibility
- [list all fixes]

### Known Limitations
- about:newtab headless mode issue (upstream Firefox)
- [list other limitations]

### Installation
Download: https://github.com/amjadiqbal/w3ai-browser/releases
Verify: spctl -a -v W3Ai\ Browser.app

### Updating
Users on 151.0.0-rc.X will automatically receive this update
Update manifest: https://updates.w3ai.dev/prod/update.xml

### Support
- Issues: https://github.com/amjadiqbal/w3ai-browser/issues
- Docs: https://github.com/amjadiqbal/w3ai-browser/wiki"

git tag -l v151.0.0
git show v151.0.0
```

### 4. Hotfix Release Tag

**When**: Critical bug found in production  
**Branch**: production (from hotfix merge)  
**Tag**: `vMAJOR.MINOR.PATCH` (patch number incremented)

```bash
git tag -a v151.0.1 -m "W3Ai Browser Hotfix Release v151.0.1

### Security Hotfix
- Base: v151.0.0
- Release Date: $(date '+%Y-%m-%d')
- Status: ✅ CRITICAL SECURITY UPDATE

### Security Issue Fixed
Vulnerability: XSS in about:logins
Severity: CRITICAL
CVE: CVE-2024-XXXXX

### Affected Versions
v151.0.0 (all users)

### Installation
Download: https://github.com/amjadiqbal/w3ai-browser/releases/tag/v151.0.1
Verify: spctl -a -v W3Ai\ Browser.app

Automatic Update:
Users should see update notification within 1 hour
Update manifest: https://updates.w3ai.dev/prod/update.xml

### Action Required
All users should update immediately

### Testing
Platform testing: macOS 12.6.3+
Regression testing: PASSED
Security review: PASSED"

git tag -l v151.0.1
git show v151.0.1
```

---

## Setting Version in Code

### Update Version File

```bash
# Create/update version file
cat > browser/config/version.txt << 'EOF'
151.0.0-dev
EOF

# Firefox auto-reads this and sets in:
# MOZ_APP_VERSION environment variable
# Used in DMG name, app version info, about:firefox

# Verify it took effect
grep -r "151.0.0" obj-x86_64-apple-darwin*/dist/W3Ai\ Browser.app/
```

### Update Branding Files

```bash
# browser/branding/w3ai/locales/en-US/brand.ftl
vim browser/branding/w3ai/locales/en-US/brand.ftl

# Update version string
-brand-version = W3Ai Browser 151.0.0-dev
-brand-shortName = W3Ai Browser
-brand-aboutHomeSnippets = Powered by Firefox & W3Ai

# browser/branding/w3ai/profile/chrome/brand/aboutLogins.properties
vim browser/branding/w3ai/profile/chrome/brand/aboutLogins.properties

# If version info needed
version = 151.0.0-dev
buildTime = 2024-04-06
```

---

## Tag Management

### List All Tags

```bash
# All tags
git tag -l

# With descriptions
git tag -l -n

# Tags matching pattern
git tag -l 'v151*'
git tag -l 'v151.0.0*'

# Show specific tag
git show v151.0.0
```

### Create Lightweight vs Annotated Tags

```bash
# Annotated tag (recommended - includes author, date, message)
git tag -a v151.0.0 -m "Release message"

# Lightweight tag (just a pointer, no metadata)
git tag v151.0.0-lightweight
```

### Delete Tags

```bash
# Delete local tag
git tag -d v151.0.0-bad

# Delete remote tag
git push origin --delete v151.0.0-bad

# Force-update tag (only if necessary and coordinated)
git tag -f -a v151.0.0 -m "Updated message"
git push -f origin v151.0.0
```

### Push Tags to GitHub

```bash
# Push specific tag
git push origin v151.0.0

# Push all tags
git push origin --tags

# Verify on GitHub
# https://github.com/amjadiqbal/w3ai-browser/tags
```

---

## Version Timeline Example

```
2024-04-01: Start development
           git checkout -b release/w3ai-151.0.0-dev
           Features added to w3ai/develop
           
2024-04-15: Feature freeze
           git tag v151.0.0-dev
           QA begins testing on release/w3ai-151.0.0-dev
           
2024-04-17: First issues found
           git tag v151.0.0-rc.1
           Bugs fixed on release branch
           
2024-04-20: All critical issues resolved
           git tag v151.0.0
           git merge release/w3ai-151.0.0-dev → production
           First production release
           
2024-04-22: Security vulnerability discovered
           git checkout -b hotfix/security-xss
           Fix applied
           git tag v151.0.1
           git merge hotfix → production + w3ai/develop
           
2024-05-01: Next development begins
           Next version: 152.0.0-dev
```

---

## Semantic Versioning Reference

```
Given a version number MAJOR.MINOR.PATCH, increment:

1. MAJOR: Incompatible API changes / Major UI overhaul / Breaking changes
2. MINOR: Add functionality in backward-compatible manner / Major features
3. PATCH: Backward-compatible bug fixes / Small updates

Examples:
1.0.0 → 1.0.1 (bugfix: theme not persisting)
1.0.1 → 1.1.0 (feature: new color system)
1.1.0 → 2.0.0 (breaking: new API structure)
```

---

## Pre-Release Versioning

For development builds, use suffixes:

```
-dev           Development version (1+ features in progress)
-alpha.N       Alpha N (feature complete, bugs expected)
-beta.N        Beta N (mostly stable, final testing)
-rc.N          Release Candidate N (ready for release, urgent fixes only)
(no suffix)    Production Release (stable, deployed)
```

Example progression:
```
151.0.0-dev
151.0.0-alpha.1
151.0.0-beta.1
151.0.0-rc.1
151.0.0-rc.2
151.0.0          ← Production
152.0.0-dev      ← Next cycle
```

---

## CI/CD Integration

### Automated Version Bumping (Future)

When implemented, CI/CD will:

```yaml
# .github/workflows/release.yml
on:
  push:
    branches: [production]

jobs:
  release:
    runs-on: macos-latest
    steps:
      - name: Bump version
        run: |
          # Read current version
          VERSION=$(cat browser/config/version.txt)
          
          # Auto-increment based on tag
          # v151.0.0 reads as PATCH+1 for next dev

      - name: Create GitHub Release
        uses: actions/create-release@v1
        with:
          tag_name: v${{ env.VERSION }}
          release_name: W3Ai Browser v${{ env.VERSION }}
          body: |
            Release notes auto-generated from commits
```

---

## CheatSheet: Quick Version Commands

```bash
# Create development release
git tag -a v151.0.0-dev -m "Development release"
git push origin v151.0.0-dev

# Create RC
git tag -a v151.0.0-rc.1 -m "Release candidate 1"
git push origin v151.0.0-rc.1

# Create production release
git tag -a v151.0.0 -m "Production release"
git push origin v151.0.0

# After hotfix
git tag -a v151.0.1 -m "Critical hotfix"
git push origin v151.0.1

# List current tags
git tag -l -n5

# Show tag details
git show v151.0.0
```
