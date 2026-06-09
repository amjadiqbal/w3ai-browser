import React from "react";
import { describe, expect, it, jest, beforeEach } from "@jest/globals";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import App from "../popup/App";
import type {
  FeatureFlagSet,
  FiatCountry,
  FiatCurrency,
  FiatOffer,
  FiatProvider,
  PublicRuntimeConfig,
  UserSetting,
} from "../shared/types";

const sendMessageMock: any = jest.fn();

jest.mock("../popup/messaging", () => ({
  sendMessage: (...args: unknown[]) => sendMessageMock(...args),
}));

const config: PublicRuntimeConfig = {
  proxyBaseUrl: "https://proxy.w3ai.io",
  proxyVersion: "v1",
  environment: "production",
  featureFlags: {
    fiatEnabled: true,
    defiEnabled: false,
    fixedRateEnabled: true,
    customTokensEnabled: false,
    testnetsEnabled: false,
    historyEnabled: true,
    referralEnabled: false,
    maintenanceMode: false,
  },
  termsUrl: "https://w3ai.io/legal/terms",
  privacyUrl: "https://w3ai.io/legal/privacy",
  supportUrl: "https://support.w3ai.io",
  changellySupportUrl: "https://support.changelly.com",
};

const flags: FeatureFlagSet = config.featureFlags;
const settings: UserSetting = {
  preferredRateType: "floating",
  slippageTolerance: 1,
  showAdvancedFees: false,
  locale: "en-US",
  currency: "USD",
  termsAccepted: true,
  onboardingCompleted: true,
};

const providers: FiatProvider[] = [{ code: "moonpay", name: "MoonPay" }];
const fiatCurrencies: FiatCurrency[] = [{ type: "fiat", ticker: "USD", name: "US Dollar" }];
const cryptoCurrencies: FiatCurrency[] = [{ type: "crypto", ticker: "BTC", name: "Bitcoin" }];
const countries: FiatCountry[] = [{ code: "US", name: "United States" }];
const offers: FiatOffer[] = [
  {
    providerCode: "moonpay",
    rate: "100000",
    invertedRate: "0.00001",
    fee: "2.5",
    amountFrom: "100",
    amountExpectedTo: "0.001",
    paymentMethodOffer: [],
  },
];

describe("Fiat popup flow", () => {
  beforeEach(() => {
    sendMessageMock.mockReset();
    sendMessageMock.mockImplementation(async (type: string, payload?: any) => {
      if (type === "GET_CONFIG") return config;
      if (type === "GET_FEATURE_FLAGS") return flags;
      if (type === "GET_ASSETS") return [];
      if (type === "GET_SETTINGS") return settings;
      if (type === "GET_PAIRS") {
        return { from: payload?.from ?? "btc", to: payload?.to ?? "eth", minAmount: 0.001, maxAmount: 1, available: true };
      }
      if (type === "FIAT_GET_PROVIDERS") return providers;
      if (type === "FIAT_GET_CURRENCIES") {
        return payload?.type === "crypto" ? cryptoCurrencies : fiatCurrencies;
      }
      if (type === "FIAT_GET_COUNTRIES") return countries;
      if (type === "FIAT_GET_OFFERS_ON_RAMP") return { offers };
      if (type === "FIAT_GET_OFFERS_OFF_RAMP") return { offers };
      throw new Error(`Unhandled message type ${type}`);
    });
  });

  it("opens fiat screen and renders offers", async () => {
    const user = userEvent.setup();
    render(<App />);

    await waitFor(() => {
      expect(screen.getByText("Exchange")).toBeTruthy();
    });

    await user.click(screen.getByRole("button", { name: "Open fiat buy and sell" }));

    await waitFor(() => {
      expect(screen.getByText("Card and bank payouts in one flow")).toBeTruthy();
    });

    await user.click(screen.getByRole("button", { name: "Get offers" }));

    await waitFor(() => {
      expect(screen.getByText("Top offers")).toBeTruthy();
      expect(screen.getByRole("button", { name: "Continue to provider" })).toBeTruthy();
    });
  });
});
