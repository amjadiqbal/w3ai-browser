# W3Ai Copilot Instructions (Branching, Release, Deployment)

These instructions are mandatory for all Copilot-assisted work in this repository.

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

## Copilot Behavior Requirements
- If the branch or target workflow is ambiguous, ask for confirmation before editing.
- If a request conflicts with these rules, propose the compliant branch/workflow and proceed only after alignment.
- When asked to release or deploy, provide the exact checklist and commands from `tools/release/DEPLOYMENT.md` and `tools/release/SERVER_SETUP.md`.
