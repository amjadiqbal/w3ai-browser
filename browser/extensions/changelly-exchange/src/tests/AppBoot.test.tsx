import React from "react";
import { describe, expect, it, jest, beforeEach } from "@jest/globals";
import { render, screen, waitFor } from "@testing-library/react";
import App from "../popup/App";
import type { FeatureFlagSet, PublicRuntimeConfig, UserSetting } from "../shared/types";

const sendMessageMock: any = jest.fn();

jest.mock("../popup/messaging", () => ({
  sendMessage: (...args: unknown[]) => sendMessageMock(...args),
}));

const config: PublicRuntimeConfig = {
  proxyBaseUrl: "https://proxy.w3ai.io",
  proxyVersion: "v1",
  environment: "production",
  featureFlags: {
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

describe("App boot resilience", () => {
  beforeEach(() => {
    sendMessageMock.mockReset();
  });

  it("keeps popup usable when assets fail to load", async () => {
    sendMessageMock.mockImplementation(async (type: string) => {
      if (type === "GET_CONFIG") return config;
      if (type === "GET_FEATURE_FLAGS") return flags;
      if (type === "GET_ASSETS") throw new Error("assets unavailable");
      if (type === "GET_SETTINGS") return settings;
      throw new Error(`Unhandled message type ${type}`);
    });

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText("Exchange")).toBeTruthy();
    });
    expect(screen.queryByText("Something went wrong")).toBeNull();
  });

  it("shows the error screen when all boot calls fail", async () => {
    sendMessageMock.mockRejectedValue(new Error("offline"));

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText("Something went wrong")).toBeTruthy();
    });
  });
});
