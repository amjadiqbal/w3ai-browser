#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
ORIGIN_HEADER="${ORIGIN_HEADER:-moz-extension://local-test}"

pass() { printf "PASS  %s\n" "$1"; }
fail() { printf "FAIL  %s\n" "$1"; exit 1; }

request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -sS -X "$method" \
      -H "Origin: $ORIGIN_HEADER" \
      -H "Content-Type: application/json" \
      --data "$data" \
      "$BASE_URL$path"
  else
    curl -sS -X "$method" \
      -H "Origin: $ORIGIN_HEADER" \
      "$BASE_URL$path"
  fi
}

expect_json() {
  local name="$1"
  local body="$2"
  echo "$body" | jq . >/dev/null 2>&1 || fail "$name (invalid JSON)"
  pass "$name"
}

echo "Running smoke tests against: $BASE_URL"

expect_json "GET /v1/config" "$(request GET /v1/config)"
expect_json "GET /v1/assets" "$(request GET /v1/assets)"
expect_json "GET /v1/feature-flags" "$(request GET /v1/feature-flags)"
expect_json "GET /v1/pairs" "$(request GET '/v1/pairs?from=btc&to=eth')"
expect_json "POST /v1/validate-address" "$(request POST /v1/validate-address '{"address":"0x1111111111111111111111111111111111111111","currency":"eth"}')"
expect_json "POST /v1/quote/floating" "$(request POST /v1/quote/floating '{"from":"btc","to":"eth","amount":0.01}')"
expect_json "POST /v1/quote/fixed" "$(request POST /v1/quote/fixed '{"from":"btc","to":"eth","amountFrom":0.01}')"

# Swap endpoints can fail with business errors depending on quote/address validity,
# but responses should still be valid JSON.
expect_json "POST /v1/swap" "$(request POST /v1/swap '{"from":"btc","to":"eth","address":"0x1111111111111111111111111111111111111111","amount":0.01,"rateType":"floating"}')"

# Optional DeFi routes (may depend on account capabilities)
expect_json "GET /v1/defi/tokens" "$(request GET '/v1/defi/tokens?chainId=1')"
expect_json "POST /v1/defi/quote" "$(request POST /v1/defi/quote '{"fromTokenAddress":"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48","toTokenAddress":"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2","amount":"1000000","chainId":1,"slippage":0.5,"walletAddress":"0x1111111111111111111111111111111111111111"}')"
expect_json "GET /v1/defi/approval" "$(request GET '/v1/defi/approval?tokenAddress=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&amount=1000000&walletAddress=0x1111111111111111111111111111111111111111&chainId=1')"
expect_json "POST /v1/defi/swap" "$(request POST /v1/defi/swap '{"intentId":"smoke-test"}')"

echo "All smoke checks completed."
