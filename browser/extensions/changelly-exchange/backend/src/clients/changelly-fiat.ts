import crypto from "node:crypto";
import { env } from "../env";

type HttpMethod = "GET" | "POST";

function getFiatPublicKey(): string | undefined {
  return env.CHANGELLY_FIAT_API_PUBLIC_KEY || env.CHANGELLY_API_KEY;
}

function getFiatPrivateKey(): string | undefined {
  return env.CHANGELLY_FIAT_API_PRIVATE_KEY || env.CHANGELLY_API_SECRET;
}

function assertFiatCredentials() {
  if (!getFiatPublicKey() || !getFiatPrivateKey()) {
    throw new Error("Fiat API credentials are not configured.");
  }
}

function decodePrivateKey(raw: string): string {
  if (raw.includes("BEGIN PRIVATE KEY") || raw.includes("BEGIN RSA PRIVATE KEY")) {
    return raw;
  }
  return Buffer.from(raw, "base64").toString("utf8");
}

function buildFiatSignature(url: string, body: unknown): string {
  assertFiatCredentials();
  const privateKeyPem = decodePrivateKey(getFiatPrivateKey() as string);
  const privateKeyObject = crypto.createPrivateKey({ key: privateKeyPem, format: "pem" });
  const payload = `${url}${JSON.stringify(body)}`;
  return crypto.sign("sha256", Buffer.from(payload), privateKeyObject).toString("base64");
}

async function request<T>(
  method: HttpMethod,
  path: string,
  params?: Record<string, string | number | undefined>,
  body?: unknown
): Promise<T> {
  assertFiatCredentials();

  const url = new URL(path, env.CHANGELLY_FIAT_API_BASE_URL);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== null && v !== "") {
        url.searchParams.append(k, String(v));
      }
    }
  }

  const message = method === "GET" ? {} : (body ?? {});
  const signature = buildFiatSignature(url.toString(), message);

  const init: RequestInit = {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Api-Key": getFiatPublicKey() as string,
      "X-Api-Signature": signature,
    },
    signal: AbortSignal.timeout(15_000),
  };

  if (method === "POST") {
    init.body = JSON.stringify(message);
  }

  const response = await fetch(url, init);

  const text = await response.text();
  const json = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const msg = json?.errorMessage || json?.message || `Fiat API HTTP ${response.status}`;
    throw new Error(msg);
  }

  return json as T;
}

export const changellyFiatClient = {
  getProviders: () => request<unknown[]>("GET", "/v1/providers"),
  getCurrencies: (query?: { type?: string | undefined; providerCode?: string | undefined; supportedFlow?: string | undefined }) =>
    request<unknown[]>("GET", "/v1/currencies", query),
  getCountries: (query?: { providerCode?: string | undefined; supportedFlow?: string | undefined }) =>
    request<unknown[]>("GET", "/v1/available-countries", query),
  getOnRampOffers: (query: Record<string, string | number | undefined>) =>
    request<unknown>("GET", "/v1/offers", query),
  getOffRampOffers: (query: Record<string, string | number | undefined>) =>
    request<unknown>("GET", "/v1/sell/offers", query),
  createOnRampOrder: (body: Record<string, unknown>) =>
    request<unknown>("POST", "/v1/orders", undefined, body),
  createOffRampOrder: (body: Record<string, unknown>) =>
    request<unknown>("POST", "/v1/sell/orders", undefined, body),
  getOrders: (query: Record<string, string | number | undefined>) =>
    request<unknown>("GET", "/v1/orders", query),
  validateAddress: (body: { currency: string; walletAddress: string; walletExtraId?: string | undefined }) =>
    request<unknown>("POST", "/v1/validate-address", undefined, body),
};
