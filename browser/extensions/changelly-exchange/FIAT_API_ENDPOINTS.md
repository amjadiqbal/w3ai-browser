# Changelly Fiat API Coverage

This extension proxy now supports the primary On-Ramp and Off-Ramp Fiat API methods from `https://fiat-api.changelly.com/docs/`.

## Authentication model

- API base URL: `https://fiat-api.changelly.com`
- Headers required by Changelly:
  - `X-Api-Key`
  - `X-Api-Signature`
- Signature algorithm: RSA-SHA256
- Signed payload format:
  - `payload = fullRequestUrl + JSON.stringify(message)`
  - For GET methods, `message` is `{}`

## Implemented endpoint mapping

- `GET /v1/providers` -> `GET /v1/fiat/providers`
- `GET /v1/currencies` -> `GET /v1/fiat/currencies`
- `GET /v1/available-countries` -> `GET /v1/fiat/countries`
- `GET /v1/offers` -> `GET /v1/fiat/offers/on-ramp`
- `POST /v1/orders` -> `POST /v1/fiat/orders/on-ramp`
- `GET /v1/sell/offers` -> `GET /v1/fiat/offers/off-ramp`
- `POST /v1/sell/orders` -> `POST /v1/fiat/orders/off-ramp`
- `GET /v1/orders` -> `GET /v1/fiat/orders`
- `POST /v1/validate-address` -> `POST /v1/fiat/validate-address`

## Frontend integration

- New popup screen: `Buy / Sell Crypto`
- Flow support:
  - Buy (On-Ramp offers + create order)
  - Sell (Off-Ramp offers + create order)
- Orders open provider checkout via `redirectUrl` in a new browser tab.
