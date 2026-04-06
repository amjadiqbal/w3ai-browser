# Firefox Update Manifests - XML File Structure

This document explains how Firefox checks for updates and how to create update manifest files.

## How Firefox Updates Work

```
User runs W3Ai Browser
       ↓
Firefox checks update interval (e.g., every 24 hours)
       ↓
Browser sends GET request to update URL (defined in about:config)
       ↓
URL points to: https://updates.w3ai.dev/channel/update.xml
       ↓
Server returns XML manifest file
       ↓
Firefox parses XML to find new version
       ↓
If new version exists, Firefox downloads .mar file
       ↓
Firefox applies update and restarts with new version
```

---

## Update Manifest XML Structure

### Basic Template

```xml
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update type="minor" version="151.0.0" extensionVersion="151.0.0" buildID="20240406000000">
    <patch type="complete" URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0.complete.mar" 
           hashFunction="sha512" 
           hashValue="a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3h4i5j6k7l8m9n0o1p2q3r4s5t6u7v8w9x0y1z2a3b4c5d6e7f8g9h0i1j2k3l4m5n6o7p8q9r0s1t2u3v4w5x6y7z8a9b0c1d2e3f4" 
           size="207000000"/>
  </update>
</updates>
```

### Full Template with Comments

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 
W3Ai Browser Update Manifest for Development Channel
This file tells Firefox where to find updates
Last Updated: 2024-04-06
-->
<updates>
  <!-- 
  Single update block = one available version
  
  Attributes:
  - type: "minor" (small update) or "major" (version upgrade)
  - version: The version number the user is updating TO (e.g., 151.0.0)
  - extensionVersion: Usually same as version
  - buildID: Build timestamp in format YYYYMMDDHHMMSS
              (e.g., 20240406143022 = 2024-04-06 @ 14:30:22 UTC)
  -->
  <update 
    type="minor" 
    version="151.0.0" 
    extensionVersion="151.0.0" 
    buildID="20240406143022"
    isCompleteUpdate="true"
    channel="dev"
  >
    <!-- 
    Patch element = the actual update file
    
    Attributes:
    - type: 
      * "complete" = full new version file (entire browser)
      * "partial" = only changed files (incremental/faster)
    - URL: Full HTTPS URL to the .mar file on your server
    - hashFunction: Algorithm used for integrity check
      * "sha512" (recommended, most secure)
      * "sha256", "sha1", "md5" (less secure, not recommended)
    - hashValue: The hash of the .mar file
      * Use: `shasum -a 512 W7AiBrowser-v151.0.0.complete.mar`
    - size: File size in bytes
      * Use: `du -b W3AiBrowser-v151.0.0.complete.mar`
    -->
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0.complete.mar" 
      hashFunction="sha512" 
      hashValue="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456" 
      size="207000000"
    />
  </update>
</updates>
```

---

## Channel-Specific Manifests

### Development Channel (`dev`)

**Location**: `https://updates.w3ai.dev/dev/update.xml`  
**Update Frequency**: Multiple times per day  
**Users**: Internal testing, developers  
**Build Channel**: w3ai/develop branch

```xml
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0-dev.2024040614" 
    extensionVersion="151.0.0" 
    buildID="20240406143022"
    channel="dev"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0-dev.complete.mar" 
      hashFunction="sha512" 
      hashValue="dev_hash_value_here_64_chars_minimum" 
      size="207000000"
    />
  </update>
</updates>
```

**Configuration File** (`browser/app/profile/firefox.js`):
```javascript
// Development channel - checks for updates every hour
pref("app.update.enabled", true);
pref("app.update.channel", "dev");
pref("app.update.url", "https://updates.w3ai.dev/dev/update.xml");
pref("app.update.interval", 3600);  // Check every hour (seconds)
```

---

### Release Candidate Channel (`rc`)

**Location**: `https://updates.w3ai.dev/rc/update.xml`  
**Update Frequency**: Once per day  
**Users**: QA testers, beta users  
**Build Channel**: release/w3ai-X.X.X-* branches

```xml
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0-rc.1" 
    extensionVersion="151.0.0" 
    buildID="20240406100000"
    channel="rc"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0-rc.1.complete.mar" 
      hashFunction="sha512" 
      hashValue="rc_hash_value_here_64_chars_minimum" 
      size="207000000"
    />
  </update>
</updates>
```

**Configuration File**:
```javascript
// RC channel - checks for updates 2x per day
pref("app.update.enabled", true);
pref("app.update.channel", "rc");
pref("app.update.url", "https://updates.w3ai.dev/rc/update.xml");
pref("app.update.interval", 43200);  // Check every 12 hours
```

---

### Production Channel (`prod`)

**Location**: `https://updates.w3ai.dev/prod/update.xml`  
**Update Frequency**: Once per week  
**Users**: General public, production deployment  
**Build Channel**: production branch

```xml
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0" 
    extensionVersion="151.0.0" 
    buildID="20240405000000"
    channel="prod"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0.complete.mar" 
      hashFunction="sha512" 
      hashValue="prod_hash_value_here_64_chars_minimum" 
      size="207000000"
    />
  </update>
</updates>
```

**Configuration File**:
```javascript
// Production channel - checks for updates 1x per day
pref("app.update.enabled", true);
pref("app.update.channel", "prod");
pref("app.update.url", "https://updates.w3ai.dev/prod/update.xml");
pref("app.update.interval", 86400);  // Check every 24 hours
```

---

## Creating Update Manifest Files

### Step-by-Step Process

```bash
# 1. Build the new version
./mach build
./mach package

# Locate the .mar file (if using MAR, otherwise DMG)
ls -lh obj-x86_64-apple-darwin*/dist/

# For now, we'll create manifests for .dmg
# (Not using .mar yet - requires additional tooling)

# 2. Get DMG file information
DMG_FILE="obj-x86_64-apple-darwin25.3.0/dist/W3AiBrowser-v151.0.0.complete.dmg"
DMG_SIZE=$(du -b "$DMG_FILE" | awk '{print $1}')
DMG_HASH=$(shasum -a 512 "$DMG_FILE" | awk '{print $1}')
BUILD_DATE=$(date '+%Y%m%d%H%M%S')

echo "File: $DMG_FILE"
echo "Size: $DMG_SIZE bytes"
echo "SHA512: $DMG_HASH"
echo "BuildID: $BUILD_DATE"

# 3. Create development manifest
cat > /tmp/dev-update.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0-dev" 
    extensionVersion="151.0.0" 
    buildID="$BUILD_DATE"
    channel="dev"
  >
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0-dev.dmg" 
      hashFunction="sha512" 
      hashValue="$DMG_HASH" 
      size="$DMG_SIZE"
    />
  </update>
</updates>
EOF

# 4. Create RC manifest
cat > /tmp/rc-update.xml << EOF
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
      hashValue="$DMG_HASH" 
      size="$DMG_SIZE"
    />
  </update>
</updates>
EOF

# 5. Create production manifest (only when releasing)
cat > /tmp/prod-update.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
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
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0.dmg" 
      hashFunction="sha512" 
      hashValue="$DMG_HASH" 
      size="$DMG_SIZE"
    />
  </update>
</updates>
EOF

# 6. Verify XML is valid
xmllint /tmp/dev-update.xml      # Should say "valid"
xmllint /tmp/rc-update.xml
xmllint /tmp/prod-update.xml

# 7. Upload to update server
# (See DEPLOYMENT.md)
```

---

## Multiple Versions in Single Manifest

You can offer **multiple update options** (complete + partial):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<updates>
  <update 
    type="minor" 
    version="151.0.0" 
    extensionVersion="151.0.0" 
    buildID="20240406000000"
  >
    <!-- Partial update: only changed files (faster, ~50MB) -->
    <patch 
      type="partial" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-151.0.0-from-151.0-rc-1.partial.mar" 
      hashFunction="sha512" 
      hashValue="partial_hash_value_here" 
      size="50000000"
    />
    
    <!-- Complete update: full browser (fallback, ~200MB) -->
    <patch 
      type="complete" 
      URL="https://updates.w3ai.dev/releases/W3AiBrowser-v151.0.0.complete.mar" 
      hashFunction="sha512" 
      hashValue="complete_hash_value_here" 
      size="207000000"
    />
  </update>
</updates>
```

Firefox will:
1. First try partial update (faster)
2. If partial fails, fallback to complete update

---

## Server Response Header Requirements

Your web server must set correct headers:

```
# Required headers
Content-Type: application/xml; charset=utf-8
Content-Length: [size in bytes]
Cache-Control: no-cache, no-store, must-revalidate
X-Content-Type-Options: nosniff

# Example nginx config:
server {
  location /update.xml {
    add_header Content-Type "application/xml; charset=utf-8";
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header X-Content-Type-Options "nosniff";
  }
}

# Example Apache config:
<Files "update.xml">
  Header set Content-Type "application/xml; charset=utf-8"
  Header set Cache-Control "no-cache, no-store, must-revalidate"
  Header set X-Content-Type-Options "nosniff"
</Files>
```

---

## Testing Your Manifest Locally

### 1. Mock Update Server

```bash
# Start simple Python HTTP server
cd /tmp
python3 -m http.server 9999

# In browser, set:
# about:config → app.update.url
# Value: http://localhost:9999/dev-update.xml
```

### 2. Force Update Check

```bash
# In browser console (about:support)
# Manually trigger update check

# Or via command line:
./mach run \
  -pref "app.update.enabled=true" \
  -pref "app.update.url=http://localhost:9999/dev-update.xml"

# Check for update notification
```

### 3. Verify Update Detection

```bash
# Tail Firefox error log
tail -f ~/.mozilla/firefox/[profile]/browser-console.log

# Look for update check logs
```

---

## Update Manifest Reference

### Attribute Reference

| Attribute | Required | Example | Notes |
|-----------|----------|---------|-------|
| type | yes | "minor" | "minor" or "major" |
| version | yes | "151.0.0" | Target version number |
| extensionVersion | yes | "151.0.0" | Usually same as version |
| buildID | yes | "20240406000000" | YYYYMMDDhhmmss format |
| channel | no | "prod" | For logging/tracking |
| URL (patch) | yes | "https://..." | Full HTTPS URL to .mar/.dmg |
| hashFunction | yes | "sha512" | sha512, sha256, sha1, md5 |
| hashValue | yes | "abc123..." | Hex hash of file |
| size | yes | "207000000" | File size in bytes |

---

## Verifying Hash Values

```bash
# Calculate SHA512 hash
shasum -a 512 W3AiBrowser-v151.0.0.dmg

# Output: abc123def456... W3AiBrowser-v151.0.0.dmg
# Copy the hash value (first part) to hashValue in XML

# Verify on another machine
echo "abc123def456...  W3AiBrowser-v151.0.0.dmg" | shasum -a 512 -c
# Output: W3AiBrowser-v151.0.0.dmg: OK
```

---

## Common Manifest Issues

| Problem | Symptom | Solution |
|---------|---------|----------|
| Invalid XML | Update fails silently | Run xmllint to validate |
| Wrong hash | File corrupts on download | Recalculate with shasum |
| Wrong size | Download hangs | Get correct size with du -b |
| HTTP not HTTPS | Security warning | Use HTTPS URLs only |
| Missing file | 404 error | Verify file exists on server |
| Stale cache | Old version offered | Set Cache-Control headers |

---

## Production Deployment

For actual deployment, see [DEPLOYMENT.md](./DEPLOYMENT.md):
- Uploading files to server
- Setting DNS records
- Configuring CDN
- Testing with real users
