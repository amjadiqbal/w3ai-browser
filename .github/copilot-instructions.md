# W3Ai Copilot Instructions (Branching, Release, Deployment)

These instructions are mandatory for all Copilot-assisted work in this repository.

## Default Preflight (Run On Every Task)
Before writing or changing any code, run this preflight flow every time:
1. Classify user intent:
   - `new-feature`: user is adding net-new functionality.
   - `existing-feature-change`: bug fix, enhancement, refactor, or style update in existing behavior.
   - `release-or-deploy`: branch promotion, tagging, manifests, server, rollout.
   - `docs-or-meta`: documentation, instructions, or non-runtime changes.
2. Detect current branch and state:
   - `git rev-parse --abbrev-ref HEAD`
   - `git status --short`
3. Decide branch action and ask user before switching/creating when needed.
4. Confirm target files using `tools/release/CODING.md`.
5. Proceed only after branch policy is satisfied.

## Intent-Aware Branch Decision
- If intent is `new-feature` and current branch is not `feature/*`, ask:
  - "This looks like a new feature. Should I create a feature branch now?"
  - Suggested dynamic branch format: `feature/<slug>`
- Build `<slug>` from user request summary:
  - lowercase
  - spaces/underscores to `-`
  - keep `[a-z0-9-]` only
  - collapse repeated dashes
  - trim leading/trailing dash
- Branch command:
  - `git checkout w3ai/develop && git pull && git checkout -b feature/<slug>`
- If user declines branch creation, continue on the current branch.

- If intent is `existing-feature-change`, use current working branch unless user requests a new one.
- If intent is `release-or-deploy`, require `release/*`, `production`, or `hotfix/*` according to release docs.
- If intent is `docs-or-meta`, current branch is acceptable unless user asks for strict branching.

## Source Of Truth
- Always treat these documents as authoritative before making workflow decisions:
  - `tools/release/README.md`
  - `tools/release/BRANCH_STRATEGY.md`
  - `tools/release/CODING.md`
  - `tools/release/MERGE_STRATEGY.md`
  - `tools/release/VERSIONING.md`
  - `tools/release/UPDATE_MANIFESTS.md`
  - `tools/release/SERVER_SETUP.md`
  - `tools/release/DEPLOYMENT.md`

## Branch Rules (Always Check First)
- Before writing code, confirm current branch.
- Default development branch is `w3ai/develop`.
- Feature work must be done on `feature/*` created from `w3ai/develop`.
- Release stabilization must be done on `release/*` branches.
- Production branch is `production` and is release-only (no direct feature development).
- Emergency fixes use `hotfix/*` from `production`, then merge back to both `production` and `w3ai/develop`.

## Code Placement Rules
- Use `tools/release/CODING.md` to choose the correct target directory before editing.
- Do not place release or deployment logic in random directories.
- Keep release and deployment process documents under `tools/release/`.

## Merge Rules
- Follow `tools/release/MERGE_STRATEGY.md`.
- Standard path: `feature/* -> w3ai/develop -> release/* -> production`.
- Use PR-based flow for feature merges.
- Use a merge commit (`--no-ff`) for release and production promotion steps.

## Version And Tag Rules
- Follow semantic versioning documented in `tools/release/VERSIONING.md`.
- Version progression: `-dev` -> `-rc.N` -> production release (no suffix) -> hotfix patch.
- Create annotated tags for release milestones.

## Update Manifest Rules
- Any update-notification change must follow `tools/release/UPDATE_MANIFESTS.md`.
- Maintain channel-specific manifests (dev, rc, prod) with correct XML structure.
- Never publish manifest entries without correct URL, hash, and size values.

## Deployment Rules
- Execute production release steps only from `tools/release/DEPLOYMENT.md`.
- Server structure, Nginx, TLS, DNS, and rollout guidance must follow `tools/release/SERVER_SETUP.md`.
- Do not invent ad-hoc deployment commands when documented steps already exist.

## Default Release Build Command (macOS)
- For `release-or-deploy` work, prefer this command as the default release pipeline:
  - `./tools/release/macos/release-build-notarize.sh --keychain-profile <profile>`
- If keychain profile is not configured, use Apple ID mode without password flags:
  - `./tools/release/macos/release-build-notarize.sh --apple-id <id> --team-id <team-id>`
  - The script securely prompts for the app-specific password.
- The script performs: `./mach build` -> `./mach package` -> notarization flow.

## Copilot Behavior Requirements
- If the branch or target workflow is ambiguous, ask for confirmation before editing.
- If a request conflicts with these rules, propose the compliant branch/workflow and proceed only after alignment.
- When asked to release or deploy, provide the exact checklist and commands from `tools/release/DEPLOYMENT.md` and `tools/release/SERVER_SETUP.md`.

## Auto Commit And Push (Default)
After completing each code task, automatically commit and push by default.
- Use this command sequence:
  - `git add -A`
  - `git commit -m "<type>(<scope>): <short summary>"`
  - `git push -u origin "$(git rev-parse --abbrev-ref HEAD)"` (first push on branch) or `git push`
- Conventional commit types: `feat`, `fix`, `refactor`, `docs`, `style`, `chore`, `test`, `build`, `ci`.
- If there are no changes, skip commit/push.
- If push fails, report the error and retry once.
- If user explicitly says not to commit or not to push, follow user instruction.
