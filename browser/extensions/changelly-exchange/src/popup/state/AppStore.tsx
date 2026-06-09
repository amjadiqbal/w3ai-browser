/**
 * Centralised React state store (useReducer based, no external library).
 * All async operations dispatch to the reducer; components read pure state.
 */

import React, {
  createContext,
  useContext,
  useReducer,
  useCallback,
  type Dispatch,
  type ReactNode,
} from "react";
import type {
  Currency,
  FeatureFlagSet,
  FloatingQuote,
  FixedQuote,
  Quote,
  PublicRuntimeConfig,
  SwapDraft,
  SwapExecutionState,
  TransactionDetail,
  UserSetting,
  ApiError,
} from "../../shared/types";
import { DEFAULT_CONFIG } from "../../config/env";

// ---------------------------------------------------------------------------
// State shape
// ---------------------------------------------------------------------------

export type Screen =
  | "onboarding"
  | "swap"
  | "fiat"
  | "token-picker-from"
  | "token-picker-to"
  | "review"
  | "pending"
  | "receipt"
  | "history"
  | "transaction-detail"
  | "settings"
  | "error";

export interface AppState {
  screen: Screen;
  config: PublicRuntimeConfig;
  featureFlags: FeatureFlagSet;
  assets: Currency[];
  assetsLoading: boolean;
  draft: SwapDraft;
  quote: Quote | null;
  quoteLoading: boolean;
  quoteError: ApiError | null;
  currentSwap: SwapExecutionState | null;
  selectedTransaction: TransactionDetail | null;
  history: TransactionDetail[];
  historyLoading: boolean;
  settings: UserSetting;
  error: ApiError | null;
  maintenanceMode: boolean;
}

const DEFAULT_SETTINGS: UserSetting = {
  preferredRateType: "floating",
  slippageTolerance: 1,
  showAdvancedFees: false,
  locale: "en-US",
  currency: "USD",
  termsAccepted: false,
  onboardingCompleted: false,
};

const DEFAULT_DRAFT: SwapDraft = {
  from: "btc",
  to: "eth",
  amountFrom: 0,
  recipientAddress: "",
  rateType: "floating",
};

export const initialState: AppState = {
  screen: "swap",
  config: DEFAULT_CONFIG,
  featureFlags: DEFAULT_CONFIG.featureFlags,
  assets: [],
  assetsLoading: true,
  draft: DEFAULT_DRAFT,
  quote: null,
  quoteLoading: false,
  quoteError: null,
  currentSwap: null,
  selectedTransaction: null,
  history: [],
  historyLoading: false,
  settings: DEFAULT_SETTINGS,
  error: null,
  maintenanceMode: false,
};

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

export type AppAction =
  | { type: "SET_SCREEN"; payload: Screen }
  | { type: "SET_CONFIG"; payload: PublicRuntimeConfig }
  | { type: "SET_FEATURE_FLAGS"; payload: FeatureFlagSet }
  | { type: "SET_ASSETS"; payload: Currency[] }
  | { type: "SET_ASSETS_LOADING"; payload: boolean }
  | { type: "SET_DRAFT"; payload: Partial<SwapDraft> }
  | { type: "SET_QUOTE"; payload: Quote | null }
  | { type: "SET_QUOTE_LOADING"; payload: boolean }
  | { type: "SET_QUOTE_ERROR"; payload: ApiError | null }
  | { type: "SET_CURRENT_SWAP"; payload: SwapExecutionState | null }
  | { type: "UPDATE_SWAP_STATUS"; payload: { status: SwapExecutionState["status"]; updatedAt: number } }
  | { type: "SET_SELECTED_TX"; payload: TransactionDetail | null }
  | { type: "SET_HISTORY"; payload: TransactionDetail[] }
  | { type: "SET_HISTORY_LOADING"; payload: boolean }
  | { type: "SET_SETTINGS"; payload: UserSetting }
  | { type: "SET_GLOBAL_ERROR"; payload: ApiError | null }
  | { type: "SET_MAINTENANCE"; payload: boolean }
  | { type: "RESET_DRAFT" }
  | { type: "CLEAR_ERROR" };

// ---------------------------------------------------------------------------
// Reducer
// ---------------------------------------------------------------------------

export function reducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case "SET_SCREEN":
      return { ...state, screen: action.payload };
    case "SET_CONFIG":
      return { ...state, config: action.payload };
    case "SET_FEATURE_FLAGS":
      return { ...state, featureFlags: action.payload };
    case "SET_ASSETS":
      return { ...state, assets: action.payload, assetsLoading: false };
    case "SET_ASSETS_LOADING":
      return { ...state, assetsLoading: action.payload };
    case "SET_DRAFT":
      return { ...state, draft: { ...state.draft, ...action.payload } };
    case "RESET_DRAFT":
      return { ...state, draft: DEFAULT_DRAFT, quote: null, quoteError: null };
    case "SET_QUOTE":
      return { ...state, quote: action.payload, quoteLoading: false, quoteError: null };
    case "SET_QUOTE_LOADING":
      return { ...state, quoteLoading: action.payload };
    case "SET_QUOTE_ERROR":
      return { ...state, quoteError: action.payload, quoteLoading: false };
    case "SET_CURRENT_SWAP":
      return { ...state, currentSwap: action.payload };
    case "UPDATE_SWAP_STATUS":
      if (!state.currentSwap) return state;
      return {
        ...state,
        currentSwap: {
          ...state.currentSwap,
          status: action.payload.status,
          updatedAt: action.payload.updatedAt,
        },
      };
    case "SET_SELECTED_TX":
      return { ...state, selectedTransaction: action.payload };
    case "SET_HISTORY":
      return { ...state, history: action.payload, historyLoading: false };
    case "SET_HISTORY_LOADING":
      return { ...state, historyLoading: action.payload };
    case "SET_SETTINGS":
      return { ...state, settings: action.payload };
    case "SET_GLOBAL_ERROR":
      return { ...state, error: action.payload };
    case "CLEAR_ERROR":
      return { ...state, error: null, screen: "swap" };
    case "SET_MAINTENANCE":
      return { ...state, maintenanceMode: action.payload };
    default:
      return state;
  }
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

const AppContext = createContext<{
  state: AppState;
  dispatch: Dispatch<AppAction>;
} | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  return (
    <AppContext.Provider value={{ state, dispatch }}>
      {children}
    </AppContext.Provider>
  );
}

export function useAppState(): AppState {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useAppState must be used within AppProvider");
  return ctx.state;
}

export function useDispatch(): Dispatch<AppAction> {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useDispatch must be used within AppProvider");
  return ctx.dispatch;
}
