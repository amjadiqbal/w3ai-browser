import {
  fetchAssets,
  fetchPair,
  validateAddress,
  fetchFloatingQuote,
  fetchFixedQuote,
  createSwap,
  fetchSwapStatus,
} from "../services/proxy-client";
import { afterEach, describe, expect, it, jest } from "@jest/globals";

const BASE = "https://proxy.w3ai.io";

function mockFetch(body: unknown, status = 200) {
  (globalThis as any).fetch = jest.fn(async () => ({
    ok: status < 400,
    status,
    headers: { get: () => null },
    json: async () => body,
    text: async () => JSON.stringify(body),
  }));
}

describe("proxy-client", () => {
  afterEach(() => jest.restoreAllMocks());

  it("fetchAssets calls GET /v1/assets and returns currencies", async () => {
    const assets = [{ id: "btc", symbol: "BTC" }];
    mockFetch(assets);
    const result = await fetchAssets();
    expect(result).toEqual(assets);
    const url = ((globalThis as any).fetch as any).mock.calls[0][0] as string;
    expect(url).toContain("/v1/assets");
  });

  it("fetchPair calls GET /v1/pairs with params", async () => {
    const pair = { from: "btc", to: "eth", minAmount: 0.001, maxAmount: 1, available: true };
    mockFetch(pair);
    const result = await fetchPair("btc", "eth");
    expect(result).toEqual(pair);
    const url = ((globalThis as any).fetch as any).mock.calls[0][0] as string;
    expect(url).toContain("from=btc");
    expect(url).toContain("to=eth");
  });

  it("validateAddress calls POST /v1/validate-address", async () => {
    const response = { address: "0xabc", currency: "eth", result: true };
    mockFetch(response);
    const result = await validateAddress("0xabc", "eth");
    expect(result.result).toBe(true);
  });

  it("fetchFloatingQuote calls POST /v1/quote/floating", async () => {
    const quote = { type: "floating", from: "btc", to: "eth", amountFrom: 0.1, estimatedAmountTo: 1.4 };
    mockFetch(quote);
    const result = await fetchFloatingQuote({ from: "btc", to: "eth", amount: 0.1 });
    expect(result).toEqual(quote);
  });

  it("fetchFixedQuote calls POST /v1/quote/fixed", async () => {
    const quote = { type: "fixed", from: "btc", to: "eth", rateId: "rid-123" };
    mockFetch(quote);
    const result = await fetchFixedQuote({ from: "btc", to: "eth", amount: 0.1 });
    expect(result).toEqual(quote);
  });

  it("createSwap calls POST /v1/swap", async () => {
    const swap = { id: "tx-abc", payinAddress: "1Addr", status: "new" };
    mockFetch(swap);
    const result = await createSwap({ from: "btc", to: "eth", address: "0xRecipient", amount: 0.1, rateType: "floating" });
    expect(result.id).toBe("tx-abc");
  });

  it("fetchSwapStatus calls GET /v1/swap/status", async () => {
    mockFetch({ id: "tx-abc", status: "waiting", updatedAt: Date.now() });
    const result = await fetchSwapStatus("tx-abc");
    expect(result.status).toBe("waiting");
  });

  it("throws ApiError with RATE_LIMITED on 429 response", async () => {
    mockFetch({ error: "RATE_LIMIT", message: "Too many requests." }, 429);
    await expect(fetchAssets()).rejects.toMatchObject({ code: "RATE_LIMITED" });
  });

  it("throws ApiError with MAINTENANCE on 503 response", async () => {
    mockFetch({ error: "SERVICE_UNAVAILABLE", message: "Service down." }, 503);
    await expect(fetchAssets()).rejects.toMatchObject({ code: "MAINTENANCE" });
  });
});
