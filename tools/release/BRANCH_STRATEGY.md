# W3Ai Browser Branch Strategy

This document explains the branching model, when to use each branch, and how code flows through the repository.

## Branch Hierarchy

```
upstream-sync (mozilla/gecko-dev/master)
       ↓ (cherry-pick + sync)
w3ai/develop (active development)
       ↓ (feature complete + tested)
release/w3ai-151.0.0-dev (release candidate)  ←→  hotfix/template (emergency fixes)
       ↓ (approved + tagged)
production (stable releases)
```

## Branch Descriptions

### 1. **upstream-sync** 
**Purpose**: Track Mozilla Firefox master branch  
**Who can push**: Release manager only  
**Rebase frequency**: Weekly (shallow fetch)  
**Use case**: Monitor upstream Firefox changes, evaluate security patches

Commands:
```bash
# Fetch upstream changes (shallow)
git fetch --depth=1 --no-tags --filter=blob:none upstream master

# View new changes
git log upstream-sync..upstream/master --oneline | head -20

# Cherry-pick specific commits to w3ai/develop
git cherry-pick <commit-hash>
```

---

### 2. **w3ai/develop** ⭐ **MAIN DEVELOPMENT BRANCH**
**Purpose**: Integration branch for all feature development  
**Who can push**: Developers (via PR), release manager  
**Protection**: Requires PR reviews before merge  
**CI/CD**: Automated builds on each push  

**YOU SHOULD BE ON THIS BRANCH FOR DAILY DEVELOPMENT**

Commands:
```bash
# Create feature branches FROM w3ai/develop
git checkout w3ai/develop
git pull origin w3ai/develop
git checkout -b feature/my-feature

# Work on feature...

# Push feature branch
git push -u origin feature/my-feature

# Create PR on GitHub for review
```

**When to merge**:
- ✅ Feature is complete and tested locally
- ✅ All tests pass (`./mach test --auto`)
- ✅ Code reviewed and approved
- ✅ No conflicts with main codebase

---

### 3. **release/w3ai-151.0.0-dev**
**Purpose**: Release candidate branch (hardening phase)  
**Who can push**: Release manager only  
**Rebase frequency**: None after creation  
**Duration**: 2-4 weeks before production release  

**Use this branch when**:
1. Feature set is frozen
2. All planned features merged to w3ai/develop
3. Testing phase begins
4. Ready to start notarization/signing

Commands:
```bash
# Create release branch from w3ai/develop
git checkout w3ai/develop
git pull origin w3ai/develop
git checkout -b release/w3ai-151.0.0-dev

# Only hotfixes go here from now on
git cherry-pick <hotfix-commit-from-hotfix/template>

# Push release branch
git push -u origin release/w3ai-151.0.0-dev
```

---

### 4. **hotfix/template**
**Purpose**: Emergency fixes for critical bugs in released version  
**Who can push**: Release manager + senior developers  
**Parent**: production  
**Merge into**: production + w3ai/develop  

**Use this branch when**:
- Critical security vulnerability discovered
- Crash in production affecting users
- Data loss bug reported

Commands:
```bash
# Create hotfix branch from production
git checkout production
git pull origin production
git checkout -b hotfix/critical-security-fix

# Fix the issue...

# Merge to production
git checkout production
git merge hotfix/critical-security-fix
git tag -a v151.0.1-hotfix-1 -m "Critical security fix"
git push origin production --tags

# Also merge to w3ai/develop to avoid regression
git checkout w3ai/develop
git merge hotfix/critical-security-fix
git push origin w3ai/develop

# Delete local and remote hotfix branch
git branch -d hotfix/critical-security-fix
git push origin --delete hotfix/critical-security-fix
```

---

### 5. **production**
**Purpose**: Stable, released version  
**Who can push**: Release manager only  
**Tags**: Semantic version tags (v151.0.0, v151.0.1, etc.)  

**What is deployed to users from THIS branch**  
**Never force-push. Use merge commits only.**

---

## Development Workflow Example

### Scenario: Adding new feature

```bash
# 1. Start on w3ai/develop
git checkout w3ai/develop
git pull origin w3ai/develop

# 2. Create feature branch
git checkout -b feature/improved-theme-engine

# 3. Make changes
# Edit files locally...

# 4. Test locally
./mach test --auto          # Run tests
./mach build                # Rebuild
./mach run                  # Manual testing

# 5. Commit with clear message
git add .
git commit -m "feat(theme): add dynamic color system for accessibility

- New CSS variables for theme switching
- Improved contrast ratio detection
- Respect user preferences for reduced motion"

# 6. Push to GitHub
git push -u origin feature/improved-theme-engine

# 7. Create PR on GitHub
# Go to: https://github.com/amjadiqbal/w3ai-browser/pull/new/feature/improved-theme-engine
# Fill in description, request reviewers

# 8. Address review feedback
# Make changes, commit, push
git add .
git commit -m "refactor(theme): simplify color-mix() logic per review"
git push origin feature/improved-theme-engine

# 9. After approval, merge to w3ai/develop
# (via GitHub UI or)
git checkout w3ai/develop
git pull origin w3ai/develop
git merge --no-ff feature/improved-theme-engine
git push origin w3ai/develop

# 10. Clean up
git branch -d feature/improved-theme-engine
git push origin --delete feature/improved-theme-engine
```

---

## When Branches Are Out of Sync

### Scenario: w3ai/develop has new commits, your feature branch is stale

```bash
# Option 1: Rebase (cleaner history)
git checkout feature/my-feature
git fetch origin
git rebase origin/w3ai/develop
git push origin feature/my-feature --force-with-lease

# Option 2: Merge (preserves history)
git checkout feature/my-feature
git fetch origin
git merge origin/w3ai/develop
git push origin feature/my-feature
```

---

## Branch Protection Rules (on GitHub)

These are enforced automatically:

| Branch | Rules |
|--------|-------|
| `w3ai/develop` | Require PR reviews (1 minimum), dismiss stale reviews, require status checks to pass |
| `production` | Require PR reviews (2 minimum), require uptodate branches, dismiss stale reviews |
| `hotfix/*` | Allow direct push for release manager only |
| `release/*` | Allow direct push for release manager only |

---

## Quick Reference: Where to Branch FROM?

| I want to... | Branch FROM | Command |
|-------------|------------|---------|
| Add a feature | w3ai/develop | `git checkout -b feature/my-feature` |
| Fix a bug in current dev | w3ai/develop | `git checkout -b bugfix/issue-123` |
| Release QA testing | w3ai/develop | `git checkout -b release/w3ai-X.X.X-dev` |
| Emergency production fix | production | `git checkout -b hotfix/critical-issue` |
| Sync with Mozilla | upstream-sync | `git merge upstream-sync` |

---

## Summary

- **You code on**: feature/* branches created from `w3ai/develop`
- **You push to**: `origin/feature/*` and open PR
- **Your PR merges to**: `w3ai/develop` after review
- **Release manager** creates `release/w3ai-X.X.X-dev` from `w3ai/develop`
- **Release manager** tags and merges to `production` when ready
- **Users get updates** from `production` branch
