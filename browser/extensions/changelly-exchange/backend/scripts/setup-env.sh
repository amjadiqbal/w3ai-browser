#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
EXAMPLE_FILE="$ROOT_DIR/.env.example"

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo "Missing template: $EXAMPLE_FILE"
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  echo ".env already exists at: $ENV_FILE"
  echo "Update CHANGELLY_API_KEY and CHANGELLY_API_SECRET if needed."
  exit 0
fi

cp "$EXAMPLE_FILE" "$ENV_FILE"
echo "Created .env from .env.example at: $ENV_FILE"
echo "Next: set CHANGELLY_API_KEY and CHANGELLY_API_SECRET in $ENV_FILE"
