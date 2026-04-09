# Complete Production Deployment Guide

This is the master deployment playbook. Follow these steps **exactly** when deploying W3Ai Browser to production.

## Pre-Deployment Checklist

Before starting, ensure:

- [ ] All features merged to `w3ai/develop`
- [ ] All tests passing: `./mach test --auto`
- [ ] Code reviewed and approved
- [ ] DMG package built successfully
- [ ] App signed with valid Developer ID
- [ ] App notarized with Apple
- [ ] Release notes prepared
- [ ] Update manifests documented
- [ ] Deployment server access verified
- [ ] Team notified of deployment schedule

---

## Building W3Ai

W3Ai can be built for macOS, Android, and iOS with different release modes. Choose the appropriate build command for your use case.

### Quick Start: Unified Build Command

Use the unified release builder for any platform:

```bash
# View all available build commands
./tools/release/release-build.sh --help

# Examples:
./tools/release/release-build.sh macos-dev              # Fast dev build for testing
./tools/release/release-build.sh macos-prod --keychain-profile my-profile  # Release build
./tools/release/release-build.sh android --dev          # Android dev build
./tools/release/release-build.sh ios --prod             # iOS production build
```

### macOS Development Build (Unsigned)

Use this for **rapid development and testing** on your own machine.

```bash
./tools/release/macos/build-dev.sh
```

**What it does:**
- Builds W3Ai application with full branding (W3Ai logo, theme)
- Creates an unsigned .dmg installer
- **No code signing** — suitable only for development
- Includes all W3Ai branding assets (icons, application name)
- Output: `obj-x86_64-apple-darwin*/dist/W3AiBrowser-*.dmg`

**When to use:**
- Testing new features locally
- Verifying branding and UI changes
- Quick iteration during development
- Running on your own development machine

**Installation:**
```bash
# Mount the DMG
open obj-x86_64-apple-darwin*/dist/W3AiBrowser-*.dmg

# Drag W3Ai Browser to Applications folder
# Or run directly without installing

# Clear macOS app cache (if updating):
rm -rf ~/Library/Caches/com.apple.nsurlsessiond  # May need this
```

**Next steps:**
Use `./mach run` to run directly from the build directory.

---

### macOS Production Build (Signed + Notarized)

Use this for **official distribution** and App Store / website releases.

```bash
# With keychain profile (recommended)
./tools/release/macos/build-prod.sh \
  --keychain-profile my-notarization-profile

# Or with Apple ID (will prompt for password)
./tools/release/macos/build-prod.sh \
  --apple-id your-email@example.com \
  --team-id ABCDEFG123
```

**What it does:**
- Builds optimized W3Ai application
- Creates .dmg installer
- **Code signs** the DMG with your Developer ID
- **Notarizes** with Apple (5-15 minutes)
- **Staples** the notarization ticket to the DMG
- Ready for distribution on website or App Store
- Output: `obj-x86_64-apple-darwin*/dist/W3AiBrowser-*.dmg` (notarized)

**Requirements:**
- Apple Developer account
- Valid Developer ID or signing certificate
- Notarization credentials configured (keychain or Apple ID)
- App-specific password (if using Apple ID)

**When to use:**
- Official releases for public distribution
- App Store submission
- Website downloads
- Beta releases for testers outside your team

**Progress:**
The script will show:
```
[1/4] Building application
[2/4] Packaging application
[3/4] Repackaging for DMG
[4/4] Signing and notarizing DMG
```

Notarization typically takes 5-15 minutes. The script waits and polls Apple's servers.

**Verification:**
```bash
# Verify notarization was successful
codesign -v --verbose=4 W3AiBrowser-*.dmg

# Check stapled ticket
stapler validate W3AiBrowser-*.dmg
```

---

### macOS Build Without Notarization

If you want to sign but skip notarization (useful for internal betas):

```bash
./tools/release/macos/build-prod.sh --no-notarize
```

---

### Android Development Build

Use this to **test on Android devices or emulators**.

```bash
./tools/release/android/build.sh --dev
```

**What it does:**
- Builds debug APK with W3Ai branding
- Includes debug symbols for troubleshooting
- **Not signed** for distribution
- Output: `obj-android*/dist/W3AiBrowser-debug.apk`

**Installation on device:**
```bash
# If device is connected via USB with ADB debugging enabled
adb install -r obj-android*/dist/W3AiBrowser-debug.apk

# Or on emulator
adb -e install -r obj-android*/dist/W3AiBrowser-debug.apk
```

---

### Android Production Build

Use this for **official distribution** on Google Play or other app stores.

```bash
./tools/release/android/build.sh --prod
```

**What it does:**
- Builds optimized APK with W3Ai branding
- Smaller file size
- Ready for signing and store submission
- Output: `obj-android*/dist/W3AiBrowser-release.apk`

**Signing and distribution:**
Requires separate signing setup. See Android documentation for app signing and Play Store submission.

---

### iOS Development Build

Use this to **test on iOS devices**.

```bash
./tools/release/ios/build.sh --dev
```

**What it does:**
- Builds debug IPA with W3Ai branding
- Suitable for testing on development devices
- Output: `obj-ios*/dist/W3AiBrowser-debug.ipa`

**Installation:**
```bash
# Connect iOS device and authorize via Xcode
# Then install the IPA:
ios-deploy -b W3AiBrowser-debug.ipa

# Or manually via Xcode's Devices window:
# 1. Connect device
# 2. Window > Devices and Simulators
# 3. Select device
# 4. Drag .ipa onto device window
```

---

### iOS Production Build

Use this for **App Store distribution**.

```bash
./tools/release/ios/build.sh --prod --team-id ABCDEFG123
```

**What it does:**
- Builds optimized IPA with W3Ai branding
- Code signed for App Store
- Ready for submission
- Output: `obj-ios*/dist/W3AiBrowser-prod.ipa`

**App Store submission:**
Use Xcode's App Store Connect integration to upload the IPA.

---

### Build Configuration Verification

Before building, verify W3Ai branding is configured:

```bash
# Check mozconfig has W3Ai branding enabled
grep "w3ai" mozconfig
# Output should include: --with-branding=browser/branding/w3ai

# Verify branding assets exist
ls -la browser/branding/w3ai/firefox.icns
ls -la browser/branding/w3ai/disk.icns
```

If branding is not configured, edit `mozconfig`:
```
ac_add_options --with-branding=browser/branding/w3ai
```

Then rebuild.

---

## Phase 1: Preparation (Days 1-3)

### Step 1.1: Create Release Branch

```bash
# Ensure w3ai/develop is up to date
git checkout w3ai/develop
git pull origin w3ai/develop

# Verify all needed features are merged
git log --oneline -20 | head

# Create release branch
git checkout -b release/w3ai-151.0.0-dev
git push -u origin release/w3ai-151.0.0-dev

# Tag development release
git tag -a v151.0.0-dev -m "Development release for QA"
git push origin v151.0.0-dev

echo "✅ Release branch created: release/w3ai-151.0.0-dev"
echo "   Tag: v151.0.0-dev"
```

### Step 1.2: Build Release Candidate

```bash
# Ensure on release branch
git checkout release/w3ai-151.0.0-dev

# Clean build
rm -rf obj-x86_64-apple-darwin*/
./mach build
./mach package

# Verify DMG is created
ls -lh obj-x86_64-apple-darwin*/dist/W3Ai\ Browser.app/

# Output should show ~207MB DMG file
# Example:
# /Volumes/.../dist/W3AiBrowser-v151.0.0-dev.dmg (207M)
```

### Step 1.3: Code Signing

```bash
# Default release command: build + package + notarize in one flow
./tools/release/macos/release-build-notarize.sh \
  --keychain-profile <profile>

# Alternative (without keychain profile)
./tools/release/macos/release-build-notarize.sh \
  --apple-id <id> \
  --team-id <team-id>

# The script prompts securely for app-specific password

# Optional validation-only mode
./tools/release/macos/release-build-notarize.sh --dry-run

# Output should include:
# ✅ Code signature valid
# ✅ Notarization ticket: [ticket-id]
# ✅ Stapling completed
```

### Step 1.4: Publish Release Candidate Tag

```bash
# After signing verification, create RC tag
git tag -a v151.0.0-rc.1 -m "Release Candidate 1

### Changes:
- Fixed theme color inconsistencies  
- Resolved about:preferences crash
- Updated localization strings

### Testing Focus:
1. Theme switching and visual consistency
2. All about:* pages
3. Toolbar and menu functionality
4. Extension compatibility"

git push origin v151.0.0-rc.1

# Create GitHub Release (optional, via web UI)
# https://github.com/amjadiqbal/w3ai-browser/releases
# Tag: v151.0.0-rc.1
```

### Step 1.5: Update Manifest for RC

```bash
# Get RC build information
RC_DMG="obj-x86_64-apple-darwin25.3.0/dist/W3AiBrowser-v151.0.0-rc.1.dmg"
RC_SIZE=$(du -b "$RC_DMG" | awk '{print $1}')
RC_HASH=$(shasum -a 512 "$RC_DMG" | awk '{print $1}')
BUILD_DATE=$(date '+%Y%m%d%H%M%S')

# Create RC update manifest
cat > tools/release/update-host/updates/rc/macos/update.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0-rc.1" 
    extensionVersion="151.0.0" 
    buildID="$BUILD_DATE"
    channel="rc"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0-rc.1.dmg" 
      hashFunction="sha512" 
      hashValue="$RC_HASH" 
      size="$RC_SIZE"
    />
  </update>
</updates>
EOF

# Validate XML
xmllint tools/release/update-host/updates/rc/macos/update.xml

# Commit manifest
git add tools/release/update-host/updates/rc/macos/update.xml
git commit -m "release: RC manifest with build date and hash"
git push origin release/w3ai-151.0.0-dev
```

---

## Phase 2: QA Testing (Days 4-14)

### Step 2.1: Distribute RC Build

```bash
# Upload RC DMG to GitHub Releases
# Download link: https://github.com/amjadiqbal/w3ai-browser/releases/tag/v151.0.0-rc.1

# Notify QA team
cat << 'MSG' | mail -s "QA: W3Ai Browser v151.0.0-rc.1 Ready" qa@platodata.io
Subject: QA Testing: W3Ai Browser v151.0.0-rc.1

Release Candidate is ready for testing:
https://github.com/amjadiqbal/w3ai-browser/releases/tag/v151.0.0-rc.1

Test Platform: macOS 12.6.3+

Key Points to Test:
1. Theme switching and visual consistency
2. All about:* pages (preferences, logins, protections, support, newtab)
3. Toolbar buttons and menus
4. Extension installation and compatibility
5. Auto-updates (if testing in production)
6. Cross-platform shortcuts

Please report issues at:
https://github.com/amjadiqbal/w3ai-browser/issues

Timeline: Testing deadline YYYY-MM-DD
MSG
```

### Step 2.2: Handle QA Feedback

**If critical bugs found:**

```bash
# Create hotfix branch
git checkout -b hotfix/rc-critical-issue

# Fix the issue
# ... edit files ...

# Test fix
./mach build
./mach test --auto
./mach run

# Commit
git commit -am "fix(rc): [description of fix]"

# Merge back to release branch
git checkout release/w3ai-151.0.0-dev
git merge --no-ff hotfix/rc-critical-issue
git push origin release/w3ai-151.0.0-dev

# Also merge to w3ai/develop to prevent regression
git checkout w3ai/develop
git merge hotfix/rc-critical-issue
git push origin w3ai/develop

# Create new RC tag
./mach build && ./mach package
git tag -a v151.0.0-rc.2 -m "Release Candidate 2 - QA fixes"
git push origin v151.0.0-rc.2

# Update RC manifest with new hash
# (repeat Step 1.5 with -rc.2 suffix)
```

**If no critical bugs after 7 days:**

```bash
# Mark as approved for production
git tag -a v151.0.0-ready -m "Approved for production release"
git push origin v151.0.0-ready

# Send notification
echo "✅ QA Approved: v151.0.0 ready for production deployment"
```

---

## Phase 3: Production Release (Day 15)

### Step 3.1: Merge to Production Branch

```bash
# Switch to production
git checkout production
git pull origin production

# Verify you're on production
git branch -vv | grep production

# Merge release branch with commit message
git merge --no-ff release/w3ai-151.0.0-dev \
  -m "release: W3Ai Browser v151.0.0

Production release based on Firefox 151.0.0a1

## Features
- W3Ai dark+neon branding system
- Improved theme engine with color tokens
- Enhanced privacy protections panel
- Updated preference interface

## Infrastructure
- Signed with Developer ID <TEAM_ID>
- Notarized by Apple
- Update manifest configured

## Tested on
- macOS 12.6.3+
- QA Approved: $(date '+%Y-%m-%d')

Build: release/w3ai-151.0.0-dev @ $(git rev-parse --short release/w3ai-151.0.0-dev)"

# Push to GitHub
git push origin production

# Verify merge in history
git log --oneline -5
```

### Step 3.2: Create Production Tag

```bash
# Create semantic version tag (no suffix)
git tag -a v151.0.0 -m "W3Ai Browser v151.0.0 - Production Release

## Release Information
- Base: Firefox 151.0.0a1
- Build Date: $(date '+%Y-%m-%d %H:%M:%S')
- Branch: production
- Status: ✅ STABLE

## Features
- W3Ai brand system with neon accent colors  
- Dark mode theme with improved contrast
- Token-based color system for consistency
- Updated privacy protections dashboard
- Enhanced preference interface

## Bug Fixes
- Fixed theme persistence across sessions
- Resolved toolbar layout issues
- Improved add-on compatibility

## Installation
- macOS 12.6.3+
- Apple Notarized: YES
- Code Signed: YES (<TEAM_ID>)

Download: https://github.com/amjadiqbal/w3ai-browser/releases/tag/v151.0.0"

# Push tag to GitHub
git push origin v151.0.0

# Verify tag
git tag -l v151.0.0 -n
```

### Step 3.3: Create Production Update Manifest

```bash
# Prepare production manifest
PROD_DMG="obj-x86_64-apple-darwin25.3.0/dist/W3AiBrowser-v151.0.0.dmg"
PROD_SIZE=$(du -b "$PROD_DMG" | awk '{print $1}')
PROD_HASH=$(shasum -a 512 "$PROD_DMG" | awk '{print $1}')
BUILD_DATE=$(date '+%Y%m%d%H%M%S')

# Create manifest
cat > tools/release/update-host/updates/prod/macos/update.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- W3Ai Browser Production Update Manifest -->
<!-- Generated: $(date '+%Y-%m-%d %H:%M:%S') -->
<!-- Channel: Production -->
<updates>
  <update 
    type="minor" 
    version="151.0.0" 
    extensionVersion="151.0.0" 
    buildID="$BUILD_DATE"
    channel="prod"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/v151.0.0/W3AiBrowser-v151.0.0.dmg" 
      hashFunction="sha512" 
      hashValue="$PROD_HASH" 
      size="$PROD_SIZE"
    />
  </update>
</updates>
EOF

# Validate
xmllint tools/release/update-host/updates/prod/macos/update.xml

# Commit manifest
git add tools/release/update-host/updates/prod/macos/update.xml
git commit -m "release: production manifest v151.0.0"
git push origin production
```

---

## Phase 4: Server Deployment (Day 15-16)

### Step 4.1: Upload Server Files

**Server Structure**:
```
/srv/w3ai-updates/
├── v151.0.0/
│   ├── W3AiBrowser-v151.0.0.dmg         (207 MB)
│   ├── checksums.txt                     (SHA512)
│   └── manifest.json                     (metadata)
├── dev/
│   └── macos/
│       └── update.xml                    (development manifest)
├── rc/
│   └── macos/
│       └── update.xml                    (RC manifest)
└── prod/
    └── macos/
        └── update.xml                    (production manifest)
```

**Upload Process**:

```bash
# 1. SSH to server
ssh deploy@updates.w3ai.dev

# 2. Create release directory
mkdir -p /srv/w3ai-updates/v151.0.0

# 3. Upload DMG from local
scp obj-x86_64-apple-darwin25.3.0/dist/W3AiBrowser-v151.0.0.dmg \
    deploy@updates.w3ai.dev:/srv/w3ai-updates/v151.0.0/

# 4. Create checksums file
ssh deploy@updates.w3ai.dev << 'SSH'
cd /srv/w3ai-updates/v151.0.0
sha512sum W3AiBrowser-v151.0.0.dmg > checksums.txt
ls -lh *
SSH

# 5. Update production manifest on server
scp tools/release/update-host/updates/prod/macos/update.xml \
    deploy@updates.w3ai.dev:/srv/w3ai-updates/prod/macos/

# 6. Verify permissions
ssh deploy@updates.w3ai.dev << 'SSH'
chmod 644 /srv/w3ai-updates/v151.0.0/*
chmod 644 /srv/w3ai-updates/prod/macos/update.xml
ls -l /srv/w3ai-updates/prod/macos/update.xml
SSH
```

### Step 4.2: Verify Server Configuration

```bash
# Test manifest is accessible
curl -I https://updates.w3ai.dev/prod/macos/update.xml
# Should return: HTTP/1.1 200 OK

# Test manifest is valid XML
curl https://updates.w3ai.dev/prod/macos/update.xml | xmllint -

# Test DMG is accessible
curl -I https://updates.w3ai.dev/v151.0.0/W3AiBrowser-v151.0.0.dmg
# Should return: HTTP/1.1 200 OK
```

### Step 4.3: Configure DNS (if needed)

```bash
# If updates.w3ai.dev is new domain:
# Add DNS A record:
#   Host: updates.w3ai.dev
#   Type: A
#   Value: [server IP address]
#
# DNS propagation: 5 minutes - 24 hours
#
# Verify with:
nslookup updates.w3ai.dev
```

### Step 4.4: Enable CDN (Optional)

For faster global distribution:

```bash
# Example: CloudFlare CDN
# 1. Go to CloudFlare dashboard
# 2. Add zone: updates.w3ai.dev
# 3. Create CNAME record:
#    - updates.w3ai.dev → [your-server-domain]
# 4. Enable caching
# 5. Set cache rules:
#    - /prod/macos/update.xml → Cache Everything, 1 hour TTL
#    - /v151.0.0/* → Cache Everything, 30 days TTL

# Verify CDN is working
curl -I https://updates.w3ai.dev/prod/macos/update.xml
# Look for: X-Cache: HIT (or MISS before first cache)
```

---

## Phase 5: Rollout & Monitoring (Day 16+)

### Step 5.1: Announce Release

```bash
# Send announcement to users
cat << 'MSG' | mail -s "🎉 W3Ai Browser v151.0.0 Released!" users@w3ai.dev
Subject: W3Ai Browser v151.0.0 Now Available

🚀 **W3Ai Browser v151.0.0 is now available!**

### What's New:
- W3Ai brand identity with neon accent colors
- Dark mode theme with improved contrast
- New token-based color system
- Enhanced privacy protections
- Improved settings interface

### Download:
https://github.com/amjadiqbal/w3ai-browser/releases/tag/v151.0.0

### update:
If you have auto-updates enabled, your browser will update automatically
within 24 hours. Manual check:
  Menu → Help → About W3Ai Browser → Check for Updates

### System Requirements:
- macOS 12.6.3 or later
- Apple-certified (Notarized)

### Need Help?
- Documentation: https://github.com/amjadiqbal/w3ai-browser/wiki
- Report Issues: https://github.com/amjadiqbal/w3ai-browser/issues
- Support: support@w3ai.dev

Thank you for using W3Ai Browser!
MSG

# Social media
# Post to Twitter, LinkedIn, etc.
```

### Step 5.2: Monitor Update Adoption

```bash
# Check update server logs
ssh deploy@updates.w3ai.dev << 'SSH'
tail -f /var/log/nginx/updates.w3ai.dev.access.log | grep update.xml

# Look for patterns:
# - /prod/macos/update.xml - update checks (1-2x per user per day)
# - /v151.0.0/W3AiBrowser-*.dmg - actual downloads
# - HTTP 304 (not modified) = users already have version
# - HTTP 200 = users downloading update
SSH

# Monitor file integrity
ssh deploy@updates.w3ai.dev << 'SSH'
cd /srv/w3ai-updates/v151.0.0
sha512sum -c checksums.txt
# All should return: OK
SSH
```

### Step 5.3: Verify Users Update

```bash
# Monitor self-reported versions (if telemetry enabled)
# Charts:
# - Count of users on v151.0.0-rc.X → decreasing
# - Count of users on v151.0.0 → increasing
# - Update adoption curve

# Expected timeline:
# - Day 1: 5-10% of users update (manual + hourly check)
# - Day 2: 30% updated (manual + regular checks)
# - Day 3: 50% updated (reaching users with daily checks)
# - Day 7: 90% updated (most users have regular check intervals)
# - Day 30: 98%+ updated (only laggy users left)
```

### Step 5.4: Monitor Bug Reports

```bash
# Watch GitHub Issues for new reports
# https://github.com/amjadiqbal/w3ai-browser/issues

# If critical bug found after release:
# 1. Create hotfix on production branch
# 2. Tag as v151.0.1
# 3. Update prod manifest
# 4. Upload to server
# 5. Notify users
# (See Phase 2.2 for hotfix process)

# ⚠️ Do NOT do rollback unless absolutely necessary
# Only create new version with fix
```

---

## Phase 6: Post-Release (Day 30+)

### Step 6.1: Archive Old Versions

```bash
# After 30 days, most users have updated
# Archive RC and dev builds
ssh deploy@updates.w3ai.dev << 'SSH'
mkdir -p /srv/w3ai-updates/archive/
mv /srv/w3ai-updates/v151.0.0-rc.* /srv/w3ai-updates/archive/
ls /srv/w3ai-updates/archive/
SSH
```

### Step 6.2: Update Documentation

```bash
# Update release notes with final stats
curl https://updates.w3ai.dev/prod/macos/update.xml > /tmp/current.xml

# Create release summary
cat > tools/release/RELEASE_SUMMARY.md << 'MD'
# W3Ai Browser v151.0.0 Release Summary

## Timeline
- **Announced**: 2024-04-15
- **Released**: 2024-04-15
- **Adoption**: 98% by 2024-05-15

## Key Metrics
- Download count: [from server logs]
- Reported issues: [from GitHub]
- Crash rate: [if telemetry enabled]
- Theme adoption: [if tracking enabled]

## What Went Well
- QA process smooth
- No critical bugs post-release
- User adoption as expected

## What to Improve
- [From retrospective]
MD

git add tools/release/RELEASE_SUMMARY.md
git commit -m "docs: W3Ai Browser v151.0.0 release summary"
git push origin production
```

### Step 6.3: Plan Next Release

```bash
# After stable release, prepare next feature development
# Reset w3ai/develop for next version

# Create development branch for v152.0.0
git checkout w3ai/develop
git pull origin w3ai/develop

# Update version file for next cycle
echo "152.0.0-dev" > browser/config/version.txt
git add browser/config/version.txt
git commit -m "chore: begin v152.0.0 development cycle"
git push origin w3ai/develop

echo "✅ Ready to start development on v152.0.0"
```

---

## Troubleshooting

### Problem: Update Not Showing to Users

```bash
# Diagnosis:
# 1. Check manifest file exists
curl https://updates.w3ai.dev/prod/macos/update.xml

# 2. Verify XML is valid
curl https://updates.w3ai.dev/prod/macos/update.xml | xmllint -

# 3. Check update interval in code
grep "app.update.interval" browser/app/profile/firefox.js

# 4. Check version number (must be higher than current)
# Current: v151.0.0-rc.1
# New in manifest: v151.0.0
# ✓ Correct: 151.0.0 > 151.0.0-rc.1

# 5. Check user's browser is set to production channel
# about:config → app.update.channel
# Should be: prod

# 6. Force update check
# Menu → Help → About → Manual check
```

### Problem: File Hash Mismatch

```bash
# If notarytool signature changed:
# Re-generate hash:
sha512sum W3AiBrowser-v151.0.0.dmg
# (New hash won't match old hash even for same build)

# Update manifest with new hash:
vim tools/release/update-host/updates/prod/macos/update.xml
# Replace hashValue with new value

# Re-upload manifest to server
```

### Problem: Rollback to Previous Version

```bash
# If critical bug in v151.0.0:
# DO NOT delete v151.0.0 from server
# Instead: Revert manifest to previous version

cat > tools/release/update-host/updates/prod/macos/update.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <!-- Temporarily point to previous stable version -->
  <update 
    type="minor" 
    version="151.0.0-rc.1" 
    extensionVersion="151.0.0" 
    buildID="20240410000000"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/v151.0.0-rc.1/W3AiBrowser-v151.0.0-rc.1.dmg" 
      hashFunction="sha512" 
      hashValue="[hash]" 
      size="[size]"
    />
  </update>
</updates>
EOF

# Users will downgrade on next update check
```

---

## Deployment Checklist

Use this before deploying:

- [ ] All tests passing
- [ ] Code reviewed
- [ ] Release branch created
- [ ] DMG signed and notarized
- [ ] QA testing complete
- [ ] Release notes ready
- [ ] Update manifests prepared
- [ ] Server access verified
- [ ] DNS/CDN configured
- [ ] Notification text written
- [ ] Monitoring setup complete
- [ ] Rollback plan documented
- [ ] Team briefed
- [ ] Deployment window scheduled
- [ ] Customer support notified

Once all checked, proceed to deployment in phases above.

---

## Release Automation (Future)

When ready to automate:

```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  workflow_dispatch:  # Manual trigger via GitHub UI

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Verify version
        run: ./tools/release/verify-version.sh
      
      - name: Generate manifests
        run: ./tools/release/generate-manifests.sh
      
      - name: Upload to server
        run: ./tools/release/deploy-to-server.sh
        env:
          SERVER_HOST: updates.w3ai.dev
          SERVER_USER: deploy
          SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
      
      - name: Verify deployment
        run: ./tools/release/verify-deployment.sh
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: obj-x86_64-apple-darwin*/dist/W3AiBrowser-*.dmg
          draft: false
```
