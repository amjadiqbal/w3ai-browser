/**
 * Proxy API client — the only network-facing module in the extension.
 * Talks exclusively to the backend proxy service; never to Changelly directly.
 * All Changelly authentication happens server-side.
 */

import type {
  AddressValidationResult,
  Currency,
  DefiIntent,
  DefiQuoteRoute,
  FeatureFlagSet,
  FixedQuote,
  FloatingQuote,
  PublicRuntimeConfig,
  TransactionDetail,
  TransactionStatus,
  TradingPair,
} from "../shared/types";
import { ApiError, ApiErrorCode } from "../shared/types";
import { DEFAULT_CONFIG } from "../config/env";

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function buildApiError(code: ApiErrorCode, message: string, recoverable = false): ApiError {
  return { code, message, recoverable };
}

let _config: PublicRuntimeConfig = DEFAULT_CONFIG;

export function setRuntimeConfig(config: PublicRuntimeConfig): void {
  _config = config;
}

function base(): string {
  return _config.proxyBaseUrl;
}

async function request<T>(
  method: "GET" | "POST",
  path: string,
  body?: unknown,
  extraHeaders?: Record<string, string>
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Extension-Version": browser.runtime.getManifest().version,
    ...extraHeaders,
  };

  try {
    const response = await fetch(`${base()}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (response.status === 429) {
      const retryAfter = response.headers.get("Retry-After");
      const err = buildApiError("RATE_LIMITED", "Too many requests. Please wait.", true);
      err.retryAfterMs = retryAfter ? parseInt(retryAfter, 10) * 1000 : 60_000;
      throw err;
    }

    if (response.status === 503) {
      throw buildApiError("MAINTENANCE", "Service temporarily unavailable.", true);
    }

    if (!response.ok) {
      let msg = `Server error ${response.status}`;
      try {
        const errBody = await response.json();
        if (errBody?.message) msg = errBody.message;
      } catch {
        /* ignore parse failures */
      }
      throw buildApiError("UNKNOWN", msg, false);
    }

    return response.json() as Promise<T>;
  } catch (err) {
    clearTimeout(timeout);
    if ((err as ApiError).code) throw err;
    if ((err as Error).name === "AbortError") {
      throw buildApiError("NETWORK_ERROR", "Request timed out.", true);
    }
    throw buildApiError("NETWORK_ERROR", (err as Error).message ?? "Network error.", true);
  }
}

// ---------------------------------------------------------------------------
// Public API surface
// ---------------------------------------------------------------------------

export async function fetchPublicConfig(): Promise<PublicRuntimeConfig> {
  return request<PublicRuntimeConfig>("GET", "/config/public");
}

export async function fetchAssets(): Promise<Currency[]> {
  return request<Currency[]>("GET", "/assets");
}

export async function fetchPair(from: string, to: string): Promise<TradingPair> {
  return request<TradingPair>("GET", `/pairs?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`);
}

export interface FloatingQuoteRequest {
  from: string;
  to: string;
  amount: number;
}

export async function fetchFloatingQuote(req: FloatingQuoteRequest): Promise<FloatingQuote> {
  return request<FloatingQuote>("POST", "/quote/floating", req);
}

export interface FixedQuoteRequest {
  from: string;
  to: string;
  amount: number;
}

export async function fetchFixedQuote(req: FixedQuoteRequest): Promise<FixedQuote> {
  return request<FixedQuote>("POST", "/quote/fixed", req);
}

export async function validateAddress(
  address: string,
  currency: string,
  extraId?: string
): Promise<AddressValidationResult> {
  return request<AddressValidationResult>("POST", "/validate/address", {
    address,
    currency,
    extraId,
  });
}

export interface CreateSwapRequest {
  from: string;
  to: string;
  amount: number;
  address: string;
  extraId?: string;
  rateType: "floating" | "fixed";
  rateId?: string;
}

export interface CreateSwapResponse {
  id: string;
  payinAddress: string;
  payinExtraId?: string;
  expectedAmountFrom: number;
  expectedAmountTo: number;
  trackingUrl?: string;
}

export async function createSwap(req: CreateSwapRequest): Promise<CreateSwapResponse> {
  return request<CreateSwapResponse>("POST", "/swap/create", req);
}

export async function fetchSwapDetail(id: string): Promise<TransactionDetail> {
  return request<TransactionDetail>("GET", `/swap/${encodeURIComponent(id)}`);
}

export async function fetchSwapStatus(id: string): Promise<TransactionStatus> {
  return request<TransactionStatus>("GET", `/swap/${encodeURIComponent(id)}/status`);
}

export async function fetchHistory(page = 1, limit = 20): Promise<TransactionDetail[]> {
  return request<TransactionDetail[]>("GET", `/history?page=${page}&limit=${limit}`);
}

// ---------------------------------------------------------------------------
// DeFi swap endpoints
// ---------------------------------------------------------------------------

export interface DefiQuoteRequest {
  fromNetwork: string;
  fromToken: string;
  toNetwork: string;
  toToken: string;
  amount: string;
  walletAddress: string;
}

export async function fetchDefiQuote(req: DefiQuoteRequest): Promise<DefiQuoteRoute> {
  return request<DefiQuoteRoute>("POST", "/defi/quote", req);
}

export interface DefiIntentRequest {
  fromNetwork: string;
  fromToken: string;
  toNetwork: string;
  toToken: string;
  amount: string;
  walletAddress: string;
}

export async function createDefiIntent(req: DefiIntentRequest): Promise<DefiIntent> {
  return request<DefiIntent>("POST", "/defi/intent", req);
}

export interface DefiApprovalRequest {
  intentId: string;
}

export async function fetchDefiApprovalContext(req: DefiApprovalRequest) {
  return request("POST", "/defi/approval-context", req);
}

export async function fetchFeatureFlags(): Promise<FeatureFlagSet> {
  const config = await fetchPublicConfig();
  return config.featureFlags;
}
