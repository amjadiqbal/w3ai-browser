# Merge Strategy - How to Merge Code

This document explains the merging strategy for W3Ai Browser development.

## Merge Levels

```
Feature Branch (feature/my-feature)
       ↓ (PR → Review → Merge)
w3ai/develop (integration)
       ↓ (Manual merge when releasing)
release/w3ai-151.0.0-dev (QA/hardening)
       ↓ (Manual merge when approved)
production (stable/deployed)
```

---

## Level 1: Feature Branch → w3ai/develop

**Who**: Developers (with PR review)  
**When**: Feature is complete and tested  
**Method**: GitHub PR (Squash or Rebase merge)

### Step-by-Step PR Workflow

```bash
# 1. On your feature branch, verify it's up to date
git checkout feature/my-feature
git fetch origin
git rebase origin/w3ai/develop  # Keep branch linear

# 2. Push to GitHub
git push origin feature/my-feature --force-with-lease

# 3. Create PR on GitHub
# - Go to: https://github.com/amjadiqbal/w3ai-browser
# - Click: New Pull Request
# - Base: w3ai/develop
# - Compare: feature/my-feature

# 4. Fill PR template:
Title: [TYPE] Brief description
- TYPE = feat:, fix:, refactor:, docs:, test:, perf:, chore:

Description:
- What does this PR do?
- Why is this change needed?
- Tested on: [device/OS]
- Attached: [screenshots/video]

Related Issues/PRs: #123 (if any)

# 5. Request reviewers (min 1)
# Assign a team member for review

# 6. Address feedback
git add .
git commit -m "review: address feedback on [specific items]"
git push origin feature/my-feature

# 7. Once approved, merge using GitHub UI
# Option A: Squash and merge (recommended for small changes)
# - Squashes all commits into one
# - Commit message: "feat: my feature description"

# Option B: Rebase and merge (recommended for complex features)
# - Preserves individual commits
# - Better for understanding commit history

# Option C: Create a merge commit (for major milestones)
# - Preserves branch context
# - Commit message: "merge: feature/my-feature into w3ai/develop"

# 8. Delete branch (GitHub UI or CLI)
git branch -d feature/my-feature
git push origin --delete feature/my-feature

# 9. Verify merged
git checkout w3ai/develop
git pull origin w3ai/develop
git log --oneline -3  # Should see your commit
```

### Commit Message Format (Conventional Commits)

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Examples**:
```
feat(theme): add dark mode support
- New CSS variables for dark palette
- Media query for prefers-color-scheme
- Tests included

Fixes #123

feat(toolbar): add custom action button
- Extends browser.xhtml with new button
- Localizes button label in en-US
- Handles onclick event

Breaking change: requires manual button repositioning

refactor(components): simplify color-mix logic
- Removed redundant nested selectors
- Simplified to 2-level hierarchy
- No visual changes

fix(about:preferences): crash on theme change
- Fixed undefined reference to themeManager
- Added null checks before property access
- Added test case for edge condition
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactor without functional change
- `perf`: Performance improvement
- `test`: Add or update tests
- `docs`: Documentation
- `chore`: Build, deps, tooling
- `ci`: CI/CD configuration
- `style`: Code formatting (not changes)

---

## Level 2: w3ai/develop → release/w3ai-X.X.X-dev

**Who**: Release manager only  
**When**: Feature set is frozen, ready for QA  
**Method**: Manual merge or rebase (no fast-forward)

### Create Release Branch

```bash
# 1. Ensure w3ai/develop is up to date
git checkout w3ai/develop
git pull origin w3ai/develop

# 2. Verify all needed features are merged
git log --oneline -20
# Review commits to ensure all features are there

# 3. Create release branch
git checkout -b release/w3ai-151.0.0-dev

# 4. Push to GitHub
git push -u origin release/w3ai-151.0.0-dev

# 5. Notify team
# Send message to team chat:
# "Release branch created: release/w3ai-151.0.0-dev
#  QA testing can now begin
#  Only hotfixes should merge into this branch
#  Expected release date: [DATE]"

# 6. Lock w3ai/develop for new features
# (optional: implement via branch protection)
```

### During Release Branch Lifecycle

**Only hotfixes merge into release/*:**

```bash
# IF critical bug found during QA:
git checkout hotfix/critical-issue
# (fix the bug)
git commit -m "fix(release): [description of fix]"

# Merge to release branch
git checkout release/w3ai-151.0.0-dev
git merge --no-ff hotfix/critical-issue
git push origin release/w3ai-151.0.0-dev

# ALSO merge back to w3ai/develop to prevent regression
git checkout w3ai/develop
git merge hotfix/critical-issue
git push origin w3ai/develop

# Delete hotfix branch
git branch -d hotfix/critical-issue
git push origin --delete hotfix/critical-issue
```

---

## Level 3: release/w3ai-X.X.X-dev → production

**Who**: Release manager only  
**When**: Release is approved, tested, signed, and notarized  
**Method**: Manual merge with semantic version tag

### Release to Production (Major Step!)

```bash
# 1. Ensure release branch is ready
git checkout release/w3ai-151.0.0-dev
git pull origin release/w3ai-151.0.0-dev

# 2. Verify all tests pass
./mach test --auto
./mach build
./mach test browser/base/content/test/

# 3. Verify DMG is signed and notarized
ls -lh obj-x86_64-apple-darwin*/dist/*.dmg
# Check file properties
spctl -a -v obj-x86_64-apple-darwin*/dist/W3Ai\ Browser.app

# 4. Create merge commit to production
git checkout production
git pull origin production
git merge --no-ff release/w3ai-151.0.0-dev \
  -m "release: W3Ai Browser v151.0.0-dev

Production release candidate based on Firefox 151.0.0a1

Features:
- W3Ai dark+neon branding
- Updated preference system
- Improved theme engine
- [list major features]

Tested on:
- macOS 12.6.3+
- Verified with spctl and notarytool

Signed and notarized: YES
Build date: $(date)
Commit: $(git rev-parse --short release/w3ai-151.0.0-dev)"

# 5. Tag the release
git tag -a v151.0.0-dev -m "W3Ai Browser v151.0.0-dev

Release: 151.0.0-dev
Base: Firefox 151.0.0a1
Build: $(date)
Branch: production

This is a development release for testing.
Not recommended for production use."

# 6. Push to GitHub
git push origin production
git push origin v151.0.0-dev

# 7. Notify team
echo "🚀 Production release created: v151.0.0-dev
   Branch: production
   Tag: git tag -l v151.0.0-dev
   Download: [GitHub Releases link]"

# 8. Release on GitHub (optional web UI)
# go to https://github.com/amjadiqbal/w3ai-browser/releases
# Create new release from tag v151.0.0-dev
# Add release notes and DMG download link
```

---

## Level 4: production → Deployment/Distribution

**Who**: DevOps/Release manager  
**When**: After successful release on GitHub  
**Method**: Manual upload to distribution server

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed steps.

---

## Special Case: Hotfix in Production

**Use when**: Critical bug/security vulnerability in deployed version

```bash
# 1. Create hotfix branch from production
git checkout production
git pull origin production
git checkout -b hotfix/critical-bug-151

# 2. Fix the issue
# ... edit files ...

# 3. Commit fix
git commit -am "fix(critical): [description]"
git commit -am "test: add test for [specific issue]"

# 4. Bump patch version in code
# vim browser/config/version.txt
# Change: 151.0.0-dev → 151.0.1-hotfix

# 5. Merge to production
git checkout production
git merge --no-ff hotfix/critical-bug-151 \
  -m "hotfix: critical security fix v151.0.1"

# 6. Tag
git tag -a v151.0.1 -m "W3Ai Browser v151.0.1 - Hotfix

Critical fix: [description]
Severity: [Critical/High]"

# 7. Also merge to w3ai/develop
git checkout w3ai/develop
git merge --no-ff hotfix/critical-bug-151 \
  -m "merge: hotfix v151.0.1 into w3ai/develop

Prevents regression in next release."

# 8. Clean up
git branch -d hotfix/critical-bug-151
git push origin production --tags
git push origin w3ai/develop
```

---

## Merge Conflict Resolution

**When conflicts occur during merge**:

```bash
# 1. If merging into your branch
git merge origin/w3ai/develop
# Conflicts appear

# 2. View conflicts
git status
git diff

# 3. Edit conflicted files
vim browser/themes/shared/file.css
# Look for: <<<<<<<, =======, >>>>>>>
# Keep the version you need, delete conflict markers

# 4. Mark resolved
git add browser/themes/shared/file.css

# 5. Complete merge
git commit -m "merge: resolve conflicts with w3ai/develop"
git push origin feature/my-feature

# 6. If merging ANOTHER branch into yours
git merge feature/other-branch
# (same process as above)
```

---

## Merge Prevention Strategies

### Prevent Accidental Commits to production

```bash
# Add git hook (local only)
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if [[ "$(git rev-parse --abbrev-ref HEAD)" == "production" ]]; then
  echo "❌ ERROR: Direct commits to 'production' branch are not allowed!"
  echo "Create a feature branch instead."
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit

# Now direct commits to production are blocked
# Must use PR merge workflow
```

### Require PR Reviews

GitHub branch protection (Admin only):
- Settings → Branches → Add rule for `production`
- ✅ Require pull request reviews (2 approvals minimum)
- ✅ Dismiss stale pull request approvals
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Include administrators

---

## Summary of Merge Paths

| From | To | Method | Who | Tags |
|------|----|---------|----|------|
| feature/* | w3ai/develop | PR (Squash/Rebase) | Any dev | None |
| w3ai/develop | release/* | Merge --no-ff | Rel. Mgr | Release tag |
| release/* | production | Merge --no-ff | Rel. Mgr | v X.X.X-dev |
| hotfix/* | production | Merge --no-ff | Rel. Mgr | v X.X.X |
| hotfix/* | w3ai/develop | Merge --no-ff | Rel. Mgr | None |
| production | (deploy) | Manual upload | DevOps | release-tag |

---

## Common Merge Patterns in Commands

```bash
# Merge with commit history preserved
git merge --no-ff feature/my-feature

# Merge and squash all commits
git merge --squash feature/my-feature
git commit -m "feat: my feature"

# Merge specific commit (cherry-pick)
git cherry-pick abc1234

# Merge multiple commits
git cherry-pick abc1234..def5678

# Rebase (rewrite history - use carefully!)
git rebase origin/w3ai/develop

# Abort merge/rebase if conflicts are too complex
git merge --abort
git rebase --abort
```
