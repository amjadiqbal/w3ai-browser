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
  const cfg = await request<{
    proxyVersion: string;
    environment: "development" | "staging" | "production";
    termsUrl: string;
    privacyUrl: string;
    changellySupportUrl: string;
    maintenanceMode: boolean;
  }>("GET", "/v1/config");

  return {
    ...DEFAULT_CONFIG,
    proxyVersion: cfg.proxyVersion,
    environment: cfg.environment,
    termsUrl: cfg.termsUrl,
    privacyUrl: cfg.privacyUrl,
    changellySupportUrl: cfg.changellySupportUrl,
    featureFlags: {
      ...DEFAULT_CONFIG.featureFlags,
      maintenanceMode: cfg.maintenanceMode,
    },
  };
}

export async function fetchAssets(): Promise<Currency[]> {
  return request<Currency[]>("GET", "/v1/assets");
}

export async function fetchPair(from: string, to: string): Promise<TradingPair> {
  return request<TradingPair>("GET", `/v1/pairs?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`);
}

export interface FloatingQuoteRequest {
  from: string;
  to: string;
  amount: number;
}

export async function fetchFloatingQuote(req: FloatingQuoteRequest): Promise<FloatingQuote> {
  return request<FloatingQuote>("POST", "/v1/quote/floating", req);
}

export interface FixedQuoteRequest {
  from: string;
  to: string;
  amount: number;
}

export async function fetchFixedQuote(req: FixedQuoteRequest): Promise<FixedQuote> {
  return request<FixedQuote>("POST", "/v1/quote/fixed", { from: req.from, to: req.to, amountFrom: req.amount });
}

export async function validateAddress(
  address: string,
  currency: string,
  extraId?: string
): Promise<AddressValidationResult> {
  return request<AddressValidationResult>("POST", "/v1/validate-address", {
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
  return request<CreateSwapResponse>("POST", "/v1/swap", req);
}

export async function fetchSwapDetail(id: string): Promise<TransactionDetail> {
  return request<TransactionDetail>("GET", `/v1/swap/detail?id=${encodeURIComponent(id)}`);
}

export async function fetchSwapStatus(id: string): Promise<TransactionStatus> {
  return request<TransactionStatus>("GET", `/v1/swap/status?id=${encodeURIComponent(id)}`);
}

export async function fetchHistory(page = 1, limit = 20): Promise<TransactionDetail[]> {
  const offset = Math.max(0, (page - 1) * limit);
  return request<TransactionDetail[]>("GET", `/v1/history?limit=${limit}&offset=${offset}`);
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
  return request<DefiQuoteRoute>("POST", "/v1/defi/quote", {
    fromTokenAddress: req.fromToken,
    toTokenAddress: req.toToken,
    amount: req.amount,
    chainId: parseInt(req.fromNetwork, 10),
    walletAddress: req.walletAddress,
    slippage: 0.5,
  });
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
  return request<DefiIntent>("POST", "/v1/defi/swap", req);
}

export interface DefiApprovalRequest {
  tokenAddress: string;
  amount: string;
  walletAddress: string;
  chainId: number;
}

export async function fetchDefiApprovalContext(req: DefiApprovalRequest) {
  return request(
    "GET",
    `/v1/defi/approval?tokenAddress=${encodeURIComponent(req.tokenAddress)}&amount=${encodeURIComponent(req.amount)}&walletAddress=${encodeURIComponent(req.walletAddress)}&chainId=${req.chainId}`
  );
}

export async function fetchFeatureFlags(): Promise<FeatureFlagSet> {
  const flags = await request<{
    fixedRateEnabled: boolean;
    defiEnabled?: boolean;
    defiSwapEnabled?: boolean;
    maintenanceMode: boolean;
  }>("GET", "/v1/feature-flags");

  return {
    ...DEFAULT_CONFIG.featureFlags,
    fixedRateEnabled: flags.fixedRateEnabled,
    defiEnabled: flags.defiEnabled ?? flags.defiSwapEnabled ?? false,
    maintenanceMode: flags.maintenanceMode,
  };
}
