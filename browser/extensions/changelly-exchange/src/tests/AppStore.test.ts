import { reducer, initialState } from "../popup/state/AppStore";
import type { AppAction, AppState } from "../popup/state/AppStore";

describe("AppStore reducer", () => {
  it("SET_SCREEN updates the screen", () => {
    const next = reducer(initialState, { type: "SET_SCREEN", payload: "history" });
    expect(next.screen).toBe("history");
  });

  it("SET_QUOTE updates quote and clears loading", () => {
    const withLoading: AppState = { ...initialState, quoteLoading: true };
    const quote = {
      type: "floating" as const,
      from: "btc",
      to: "eth",
      amountFrom: 0.1,
      estimatedAmountTo: 1.42,
      rate: 14.2,
      networkFee: 0.001,
      expiresAt: Date.now() + 30_000,
    };
    const next = reducer(withLoading, { type: "SET_QUOTE", payload: quote });
    expect(next.quote).toEqual(quote);
    expect(next.quoteLoading).toBe(false);
    expect(next.quoteError).toBeNull();
  });

  it("SET_QUOTE with null clears quote", () => {
    const withQuote: AppState = { ...initialState, quote: {} as any };
    const next = reducer(withQuote, { type: "SET_QUOTE", payload: null });
    expect(next.quote).toBeNull();
  });

  it("SET_DRAFT merges draft fields", () => {
    const next = reducer(initialState, { type: "SET_DRAFT", payload: { from: "btc" } });
    expect(next.draft.from).toBe("btc");
    expect(next.draft.to).toBe(initialState.draft.to);
  });

  it("RESET_DRAFT restores defaults", () => {
    const modified: AppState = {
      ...initialState,
      draft: { ...initialState.draft, from: "eth", amountFrom: 10 },
    };
    const next = reducer(modified, { type: "RESET_DRAFT" });
    expect(next.draft.from).toBe(initialState.draft.from);
    expect(next.draft.amountFrom).toBe(0);
  });

  it("SET_ASSETS updates assets and marks not loading", () => {
    const loading: AppState = { ...initialState, assetsLoading: true };
    const assets = [{ id: "btc", symbol: "BTC" }] as any;
    const next = reducer(loading, { type: "SET_ASSETS", payload: assets });
    expect(next.assets).toHaveLength(1);
    expect(next.assetsLoading).toBe(false);
  });

  it("CLEAR_ERROR clears the error and goes to swap screen", () => {
    const errored: AppState = { ...initialState, error: { message: "oops", code: "INTERNAL_ERROR" } as any, screen: "error" };
    const next = reducer(errored, { type: "CLEAR_ERROR" });
    expect(next.error).toBeNull();
    expect(next.screen).toBe("swap");
  });
});
