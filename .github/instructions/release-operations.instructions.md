---
applyTo: "**"
description: "Use when handling branches, merges, version tags, release prep, production deployment, or update manifest tasks in W3Ai browser."
---

# Release Operations Guardrails

Always enforce this order before implementing tasks:
1. Confirm current branch and workflow stage.
2. Confirm target files from `tools/release/CODING.md`.
3. Execute merge, tag, and deployment steps only from release docs.

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

## Safety Requirements
- Never perform feature development directly on `production`.
- Never skip manifest hash/size validation when publishing updates.
- Never improvise deployment flow when documented steps exist.
- If request and branch policy conflict, ask and realign first.
