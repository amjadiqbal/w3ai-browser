---
applyTo: "**"
description: "Use when handling branches, merges, version tags, release prep, production deployment, or update manifest tasks in W3Ai browser."
---

# Release Operations Guardrails

Always enforce this order before implementing tasks:
1. Confirm current branch and workflow stage.
2. Confirm target files from `tools/release/CODING.md`.
3. Execute merge, tag, and deployment steps only from release docs.

## Mandatory Preflight Workflow
Run this before any implementation:
1. Classify request intent: `new-feature`, `existing-feature-change`, `release-or-deploy`, `docs-or-meta`.
2. Inspect git context:
	- `git rev-parse --abbrev-ref HEAD`
	- `git status --short`
3. Branch routing:
	- For `new-feature` outside `feature/*`, ask to create a new feature branch.
	- Build branch name dynamically as `feature/<slug>` from user request text.
	- If user says no, continue on current branch.
4. Validate applicable release document before action.

## Required Branch Selection
- `feature/*`: new feature development from `w3ai/develop`.
- `w3ai/develop`: integration branch for ongoing work.
- `release/*`: release candidate stabilization and QA fixes.
- `production`: stable releases only.
- `hotfix/*`: emergency production fixes.

## Required References
- `tools/release/BRANCH_STRATEGY.md`
- `tools/release/MERGE_STRATEGY.md`
- `tools/release/VERSIONING.md`
- `tools/release/UPDATE_MANIFESTS.md`
- `tools/release/SERVER_SETUP.md`
- `tools/release/DEPLOYMENT.md`

## Default macOS Release Command
- Use `./tools/release/macos/release-build-notarize.sh --keychain-profile <profile>` as the default release build command.
- The command runs build, package, and notarization in one flow.
- If keychain profile is unavailable, use `--apple-id` and `--team-id`; the script prompts securely for password input.

## Safety Requirements
- Never perform feature development directly on `production`.
- Never skip manifest hash/size validation when publishing updates.
- Never improvise deployment flow when documented steps exist.
- If request and branch policy conflict, ask and realign first.

## Edit Graph Requirement (Rollback Map)
For every task that edits files, report an `Edit Graph` in the final response:
1. List each edited file with exact changed line ranges from diff hunks.
2. Use format: `<path>: <fromLine>-<toLine> | <short change summary>`.
3. Provide a quick revert command for each file: `git checkout -- <path>`.
4. Mention `git restore -p <path>` when partial hunk-level revert is more appropriate.
5. Keep entries limited to files changed in the current task.

## Change Tree Requirement (Visual Audit Log)
After every commit, run the change tree generator and display its output in the response:
```
python3 tools/changelog/change-tree.py --recent
```
- `--recent` shows the last 10 commits.
- Full history is always written to `tools/changelog/CHANGE_TREE.md`.
- Never skip this step after a commit.

## Default Commit/Push Requirement
Unless user opts out, complete tasks with automatic commit and push:
1. `git add -A`
2. `git commit -m "<type>(<scope>): <summary>"`
3. `git push -u origin "$(git rev-parse --abbrev-ref HEAD)"` (or `git push`)

Use conventional commit types (`feat`, `fix`, `refactor`, `docs`, `style`, `chore`, `test`, `build`, `ci`).
If the user requests including prior uncommitted work from the same active task, include those files in the same commit.
