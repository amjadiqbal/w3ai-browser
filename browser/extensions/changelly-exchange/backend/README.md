# Changelly Proxy Backend

This service holds Changelly credentials server-side and signs privileged API calls.

## Secure API Key Setup (never commit)

1. Create `.env` from template:

```bash
npm run env:setup
```

2. Fill these required values in `.env`:
- `CHANGELLY_API_KEY`
- `CHANGELLY_API_SECRET`
- `CHANGELLY_FIAT_API_PUBLIC_KEY` (for Fiat API)
- `CHANGELLY_FIAT_API_PRIVATE_KEY` (for Fiat API, PEM or base64-encoded PEM)

If Fiat-specific keys are not provided, the backend falls back to
`CHANGELLY_API_KEY` and `CHANGELLY_API_SECRET` so Fiat features can still be
visible during local testing.

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

## Fiat API routes in this proxy

- `GET /v1/fiat/providers`
- `GET /v1/fiat/currencies`
- `GET /v1/fiat/countries`
- `GET /v1/fiat/offers/on-ramp`
- `GET /v1/fiat/offers/off-ramp`
- `POST /v1/fiat/orders/on-ramp`
- `POST /v1/fiat/orders/off-ramp`
- `GET /v1/fiat/orders`
- `POST /v1/fiat/validate-address`

## Live smoke test against real Changelly credentials

With backend running and `.env` configured:

```bash
bash scripts/smoke-all-endpoints.sh
```

This script calls all proxy endpoints and prints PASS/FAIL per route.
