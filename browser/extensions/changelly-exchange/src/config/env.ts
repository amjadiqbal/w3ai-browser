/**
 * Public runtime configuration — contains only non-secret values.
 * This file may be generated at build time for different environments.
 * NEVER place private keys or credentials here.
 */

import type { PublicRuntimeConfig } from "../shared/types";

declare const __CHANGELLY_ENV__: string;
declare const __PROXY_BASE_URL__: string;
declare const __PROXY_VERSION__: string;

const env = (typeof __CHANGELLY_ENV__ !== "undefined" ? __CHANGELLY_ENV__ : "development") as
  | "development"
  | "staging"
  | "production";

const proxyBaseUrl =
  typeof __PROXY_BASE_URL__ !== "undefined"
    ? __PROXY_BASE_URL__
    : "https://proxy.w3ai.io";

const proxyVersion =
  typeof __PROXY_VERSION__ !== "undefined"
    ? __PROXY_VERSION__
    : "1";

export const DEFAULT_CONFIG: PublicRuntimeConfig = {
  proxyBaseUrl,
  proxyVersion,
  environment: env,
  featureFlags: {
    defiEnabled: false,
    fixedRateEnabled: true,
    customTokensEnabled: false,
    testnetsEnabled: env !== "production",
    historyEnabled: true,
    referralEnabled: false,
    maintenanceMode: false,
  },
  termsUrl: "https://w3ai.io/legal/terms",
  privacyUrl: "https://w3ai.io/legal/privacy",
  supportUrl: "https://support.w3ai.io",
  changellySupportUrl: "https://support.changelly.com",
};

export const QUOTE_TTL_FLOATING_SECONDS = 30;
export const QUOTE_TTL_FIXED_SECONDS = 900;
export const STATUS_POLL_INTERVAL_MS = 10_000;
export const QUOTE_DEBOUNCE_MS = 600;
export const MAX_SWAP_RETRIES = 3;
export const RETRY_BACKOFF_BASE_MS = 1_000;
