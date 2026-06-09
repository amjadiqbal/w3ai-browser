/**
 * Root application component — handles routing between screens.
 */

import React, { useEffect } from "react";
import { AppProvider, useAppState, useDispatch } from "./state/AppStore";
import { sendMessage } from "./messaging";
import type { Currency, FeatureFlagSet, PublicRuntimeConfig, UserSetting } from "../shared/types";
import { DEFAULT_CONFIG } from "../config/env";

// Screens
import OnboardingScreen from "./screens/OnboardingScreen";
import SwapScreen from "./screens/SwapScreen";
import TokenPickerScreen from "./screens/TokenPickerScreen";
import ReviewScreen from "./screens/ReviewScreen";
import PendingScreen from "./screens/PendingScreen";
import ReceiptScreen from "./screens/ReceiptScreen";
import HistoryScreen from "./screens/HistoryScreen";
import TransactionDetailScreen from "./screens/TransactionDetailScreen";
import SettingsScreen from "./screens/SettingsScreen";
import MaintenanceBanner from "./components/MaintenanceBanner";
import ErrorScreen from "./screens/ErrorScreen";

function RouterInner() {
  const state = useAppState();
  const dispatch = useDispatch();

  useEffect(() => {
    let mounted = true;

    async function boot() {
      const [configRes, flagsRes, assetsRes, settingsRes] = await Promise.allSettled([
        sendMessage<PublicRuntimeConfig>("GET_CONFIG"),
        sendMessage<FeatureFlagSet>("GET_FEATURE_FLAGS"),
        sendMessage<Currency[]>("GET_ASSETS"),
        sendMessage<UserSetting>("GET_SETTINGS"),
      ]);

      if (!mounted) return;

      const failedSources: string[] = [];

      if (configRes.status === "fulfilled") {
        dispatch({ type: "SET_CONFIG", payload: configRes.value });
      } else {
        failedSources.push("config");
      }

      const flags =
        flagsRes.status === "fulfilled" ? flagsRes.value : DEFAULT_CONFIG.featureFlags;
      dispatch({ type: "SET_FEATURE_FLAGS", payload: flags });
      if (flagsRes.status !== "fulfilled") {
        failedSources.push("feature flags");
      }

      if (assetsRes.status === "fulfilled") {
        dispatch({ type: "SET_ASSETS", payload: assetsRes.value });
      } else {
        failedSources.push("assets");
        dispatch({ type: "SET_ASSETS", payload: [] });
      }

      if (settingsRes.status === "fulfilled") {
        dispatch({ type: "SET_SETTINGS", payload: settingsRes.value });
        if (!settingsRes.value.onboardingCompleted) {
          dispatch({ type: "SET_SCREEN", payload: "onboarding" });
        }
      } else {
        failedSources.push("settings");
      }

      if (flags.maintenanceMode) {
        dispatch({ type: "SET_MAINTENANCE", payload: true });
      }

      if (failedSources.length === 4) {
        dispatch({
          type: "SET_GLOBAL_ERROR",
          payload: {
            code: "NETWORK_ERROR",
            message: "Unable to load extension data. Check proxy/backend connectivity.",
            recoverable: true,
          } as any,
        });
        return;
      }

      dispatch({ type: "SET_GLOBAL_ERROR", payload: null });
      if (failedSources.length > 0) {
        console.warn(`[changelly] boot degraded, failed: ${failedSources.join(", ")}`);
      }
    }

    boot();
    return () => { mounted = false; };
  }, [dispatch]);

  if (state.error && !state.maintenanceMode) {
    return (
      <>
        {state.maintenanceMode && <MaintenanceBanner />}
        <ErrorScreen />
      </>
    );
  }

  return (
    <div className="app-shell">
      {state.maintenanceMode && <MaintenanceBanner />}
      {state.screen === "onboarding" && <OnboardingScreen />}
      {state.screen === "swap" && <SwapScreen />}
      {(state.screen === "token-picker-from" || state.screen === "token-picker-to") && (
        <TokenPickerScreen side={state.screen === "token-picker-from" ? "from" : "to"} />
      )}
      {state.screen === "review" && <ReviewScreen />}
      {state.screen === "pending" && <PendingScreen />}
      {state.screen === "receipt" && <ReceiptScreen />}
      {state.screen === "history" && <HistoryScreen />}
      {state.screen === "transaction-detail" && <TransactionDetailScreen />}
      {state.screen === "settings" && <SettingsScreen />}
    </div>
  );
}

export default function App() {
  return (
    <AppProvider>
      <RouterInner />
    </AppProvider>
  );
}
