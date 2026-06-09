/**
 * Background service worker.
 * Owns all state mutations, API calls, and long-running tasks.
 * The popup communicates exclusively through browser.runtime.sendMessage.
 */

import {
  fetchPublicConfig,
  fetchAssets,
  fetchPair,
  fetchFloatingQuote,
  fetchFixedQuote,
  validateAddress,
  createSwap,
  fetchSwapDetail,
  fetchSwapStatus,
  fetchHistory,
  fetchDefiQuote,
  createDefiIntent,
  fetchDefiApprovalContext,
  setRuntimeConfig,
  fetchFeatureFlags,
  fetchFiatProviders,
  fetchFiatCurrencies,
  fetchFiatCountries,
  fetchFiatOnRampOffers,
  fetchFiatOffRampOffers,
  createFiatOnRampOrder,
  createFiatOffRampOrder,
  fetchFiatOrders,
  validateFiatAddress,
} from "../services/proxy-client";
import { DEFAULT_CONFIG, STATUS_POLL_INTERVAL_MS } from "../config/env";
import type {
  ExtensionMessage,
  ExtensionMessageResponse,
  MessageType,
  PublicRuntimeConfig,
  SwapExecutionState,
  UserSetting,
  FeatureFlagSet,
} from "../shared/types";

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let runtimeConfig: PublicRuntimeConfig = DEFAULT_CONFIG;
let featureFlags: FeatureFlagSet = DEFAULT_CONFIG.featureFlags;
let pollAlarmName: string | null = null;

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

async function init(): Promise<void> {
  try {
    runtimeConfig = await fetchPublicConfig();
    const liveFlags = await fetchFeatureFlags();
    runtimeConfig = {
      ...runtimeConfig,
      featureFlags: {
        ...runtimeConfig.featureFlags,
        ...liveFlags,
      },
    };
    setRuntimeConfig(runtimeConfig);
    featureFlags = runtimeConfig.featureFlags;
    await browser.storage.local.set({ runtimeConfig, featureFlags });
  } catch {
    const stored = await browser.storage.local.get(["runtimeConfig", "featureFlags"]);
    if (stored.runtimeConfig) runtimeConfig = stored.runtimeConfig as PublicRuntimeConfig;
    if (stored.featureFlags) featureFlags = stored.featureFlags as FeatureFlagSet;
  }

  await resumeInFlightSwap();
}

// ---------------------------------------------------------------------------
// In-flight swap recovery
// ---------------------------------------------------------------------------

async function resumeInFlightSwap(): Promise<void> {
  const stored = await browser.storage.local.get("currentSwap");
  const swap = stored.currentSwap as SwapExecutionState | undefined;
  if (!swap) return;

  const terminal: SwapExecutionState["status"][] = ["finished", "failed", "refunded", "expired", "overdue"];
  if (terminal.includes(swap.status)) return;

  startStatusPolling(swap.id);
}

function startStatusPolling(swapId: string): void {
  if (pollAlarmName) {
    browser.alarms.clear(pollAlarmName);
  }
  pollAlarmName = `status-poll-${swapId}`;
  browser.alarms.create(pollAlarmName, {
    periodInMinutes: STATUS_POLL_INTERVAL_MS / 60_000,
  });
}

function stopStatusPolling(): void {
  if (pollAlarmName) {
    browser.alarms.clear(pollAlarmName);
    pollAlarmName = null;
  }
}

browser.alarms.onAlarm.addListener(async (alarm) => {
  if (!alarm.name.startsWith("status-poll-")) return;
  const swapId = alarm.name.replace("status-poll-", "");

  try {
    const statusResp = await fetchSwapStatus(swapId);
    const stored = await browser.storage.local.get("currentSwap");
    const current = stored.currentSwap as SwapExecutionState | undefined;
    if (current && current.id === swapId) {
      const updated: SwapExecutionState = {
        ...current,
        status: statusResp.status,
        updatedAt: statusResp.updatedAt,
      };
      await browser.storage.local.set({ currentSwap: updated });

      const terminal: SwapExecutionState["status"][] = ["finished", "failed", "refunded", "expired", "overdue"];
      if (terminal.includes(statusResp.status)) {
        stopStatusPolling();
        try {
          await browser.notifications.create(`swap-done-${swapId}`, {
            type: "basic",
            iconUrl: browser.runtime.getURL("icons/icon-48.png"),
            title: "W3Ai Exchange",
            message:
              statusResp.status === "finished"
                ? "Your swap is complete!"
                : `Swap ${statusResp.status}.`,
          });
        } catch {
          /* notifications optional */
        }
      }
    }
  } catch {
    /* silently ignore transient poll failures */
  }
});

// ---------------------------------------------------------------------------
// Message handler
// ---------------------------------------------------------------------------

type Handler = (payload: unknown) => Promise<unknown>;

const handlers: Partial<Record<MessageType, Handler>> = {
  GET_CONFIG: async () => runtimeConfig,

  GET_FEATURE_FLAGS: async () => featureFlags,

  GET_ASSETS: async () => fetchAssets(),

  GET_PAIRS: async (payload) => {
    const { from, to } = payload as { from: string; to: string };
    return fetchPair(from, to);
  },

  GET_QUOTE: async (payload) => {
    const { from, to, amount, rateType } = payload as {
      from: string;
      to: string;
      amount: number;
      rateType: "floating" | "fixed";
    };
    if (rateType === "fixed") {
      return fetchFixedQuote({ from, to, amount });
    }
    return fetchFloatingQuote({ from, to, amount });
  },

  VALIDATE_ADDRESS: async (payload) => {
    const { address, currency, extraId } = payload as {
      address: string;
      currency: string;
      extraId?: string;
    };
    return validateAddress(address, currency, extraId);
  },

  CREATE_SWAP: async (payload) => {
    const req = payload as Parameters<typeof createSwap>[0];
    const result = await createSwap(req);
    const stored = await browser.storage.local.get("currentSwap");
    const prev = stored.currentSwap as SwapExecutionState | undefined;
    const state: SwapExecutionState = {
      id: result.id,
      payinAddress: result.payinAddress,
      payinExtraId: result.payinExtraId,
      expectedAmountFrom: result.expectedAmountFrom,
      expectedAmountTo: result.expectedAmountTo,
      from: req.from,
      to: req.to,
      recipientAddress: req.address,
      status: "waiting",
      createdAt: Date.now(),
      updatedAt: Date.now(),
      trackingUrl: result.trackingUrl,
    };
    // Append to history
    const histStored = await browser.storage.local.get("swapHistory");
    const history: SwapExecutionState[] = (histStored.swapHistory as SwapExecutionState[]) ?? [];
    history.unshift(state);
    await browser.storage.local.set({ currentSwap: state, swapHistory: history.slice(0, 100) });
    startStatusPolling(result.id);
    return { result, state };
  },

  GET_SWAP_STATUS: async (payload) => {
    const { id } = payload as { id: string };
    return fetchSwapStatus(id);
  },

  GET_HISTORY: async (payload) => {
    const { page, limit } = (payload as { page?: number; limit?: number }) ?? {};
    const remote = await fetchHistory(page ?? 1, limit ?? 20).catch(() => []);
    const localStored = await browser.storage.local.get("swapHistory");
    const local: SwapExecutionState[] = (localStored.swapHistory as SwapExecutionState[]) ?? [];
    // Merge by id, remote wins
    const byId = new Map<string, SwapExecutionState | (typeof remote)[0]>();
    local.forEach((s) => byId.set(s.id, s));
    remote.forEach((r) => byId.set(r.id, r));
    return [...byId.values()].sort((a, b) => b.createdAt - a.createdAt);
  },

  GET_SETTINGS: async () => {
    const stored = await browser.storage.local.get("userSettings");
    return stored.userSettings as UserSetting ?? getDefaultSettings();
  },

  SAVE_SETTINGS: async (payload) => {
    await browser.storage.local.set({ userSettings: payload });
    return { ok: true };
  },

  DEFI_GET_QUOTE: async (payload) => {
    if (!featureFlags.defiEnabled) throw { code: "PAIR_UNAVAILABLE", message: "DeFi swap not available.", recoverable: false };
    return fetchDefiQuote(payload as Parameters<typeof fetchDefiQuote>[0]);
  },

  DEFI_CREATE_INTENT: async (payload) => {
    if (!featureFlags.defiEnabled) throw { code: "PAIR_UNAVAILABLE", message: "DeFi swap not available.", recoverable: false };
    const result = await createDefiIntent(payload as Parameters<typeof createDefiIntent>[0]);
    await browser.storage.local.set({ currentDefiIntent: result });
    return result;
  },

  DEFI_GET_APPROVAL: async (payload) => {
    return fetchDefiApprovalContext(payload as Parameters<typeof fetchDefiApprovalContext>[0]);
  },

  FIAT_GET_PROVIDERS: async () => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatProviders();
  },

  FIAT_GET_CURRENCIES: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatCurrencies(payload as Parameters<typeof fetchFiatCurrencies>[0]);
  },

  FIAT_GET_COUNTRIES: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatCountries(payload as Parameters<typeof fetchFiatCountries>[0]);
  },

  FIAT_GET_OFFERS_ON_RAMP: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatOnRampOffers(payload as Parameters<typeof fetchFiatOnRampOffers>[0]);
  },

  FIAT_GET_OFFERS_OFF_RAMP: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatOffRampOffers(payload as Parameters<typeof fetchFiatOffRampOffers>[0]);
  },

  FIAT_CREATE_ORDER_ON_RAMP: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return createFiatOnRampOrder(payload as Parameters<typeof createFiatOnRampOrder>[0]);
  },

  FIAT_CREATE_ORDER_OFF_RAMP: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return createFiatOffRampOrder(payload as Parameters<typeof createFiatOffRampOrder>[0]);
  },

  FIAT_GET_ORDERS: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return fetchFiatOrders(payload as Parameters<typeof fetchFiatOrders>[0]);
  },

  FIAT_VALIDATE_ADDRESS: async (payload) => {
    if (!featureFlags.fiatEnabled) {
      throw { code: "PAIR_UNAVAILABLE", message: "Fiat API is not enabled.", recoverable: false };
    }
    return validateFiatAddress(payload as Parameters<typeof validateFiatAddress>[0]);
  },
};

function getDefaultSettings(): UserSetting {
  return {
    preferredRateType: "floating",
    slippageTolerance: 1,
    showAdvancedFees: false,
    locale: navigator.language || "en-US",
    currency: "USD",
    termsAccepted: false,
    onboardingCompleted: false,
  };
}

browser.runtime.onMessage.addListener(
  (message: ExtensionMessage, _sender): Promise<ExtensionMessageResponse> => {
    const handler = handlers[message.type];
    if (!handler) {
      return Promise.resolve({
        success: false,
        requestId: message.requestId,
        error: { code: "UNKNOWN", message: `Unknown message type: ${message.type}`, recoverable: false },
      });
    }

    return handler(message.payload)
      .then((data) => ({ success: true, requestId: message.requestId, data }))
      .catch((err) => ({
        success: false,
        requestId: message.requestId,
        error: err.code
          ? err
          : { code: "UNKNOWN", message: String(err), recoverable: false },
      }));
  }
);

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

init().catch(console.error);

browser.runtime.onInstalled.addListener(async (details) => {
  if (details.reason === "install") {
    await browser.storage.local.set({ firstInstall: true });
  }
});

