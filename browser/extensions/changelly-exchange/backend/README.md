# Changelly Proxy Backend

This service holds Changelly credentials server-side and signs privileged API calls.

## Secure API Key Setup (never commit)

1. Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

2. Fill these required values in `.env`:
- `CHANGELLY_API_KEY`
- `CHANGELLY_API_SECRET`

3. Keep `.env` local only:
- `backend/.gitignore` excludes `.env*`
- Do not commit real secrets

## Run locally

```bash
npm install
npm run dev
```

Server defaults to `http://127.0.0.1:3000`.

## Run tests

```bash
npm test -- --runInBand
```

This includes route coverage for all exposed `/v1/*` endpoints.

## Live smoke test against real Changelly credentials

With backend running and `.env` configured:

```bash
bash scripts/smoke-all-endpoints.sh
```

This script calls all proxy endpoints and prints PASS/FAIL per route.
