import { buildApp } from "../../index";
import type { FastifyInstance } from "fastify";

jest.mock("../../clients/changelly-exchange", () => ({
  changelyExchangeClient: {
    getCurrenciesFull: jest.fn().mockResolvedValue([{ id: "btc", symbol: "BTC" }]),
    getPairsParams: jest.fn().mockResolvedValue({ from: "btc", to: "eth", minAmount: 0.01, maxAmount: 10, available: true }),
    getExchangeAmount: jest.fn().mockResolvedValue({ type: "floating", from: "btc", to: "eth", amountFrom: 0.1, estimatedAmountTo: 1.1 }),
    getFixRateForAmount: jest.fn().mockResolvedValue({ type: "fixed", from: "btc", to: "eth", amountFrom: 0.1, amountTo: 1.0, rateId: "rid-1" }),
    validateAddress: jest.fn().mockResolvedValue({ address: "0xabc", currency: "eth", result: true }),
    createTransaction: jest.fn().mockResolvedValue({ id: "tx-float", payinAddress: "1btc", expectedAmountFrom: 0.1, expectedAmountTo: 1.1, trackingUrl: "https://track" }),
    createFixTransaction: jest.fn().mockResolvedValue({ id: "tx-fix", payinAddress: "1btc", expectedAmountFrom: 0.1, expectedAmountTo: 1.0, trackingUrl: "https://track" }),
    getStatus: jest.fn().mockResolvedValue("waiting"),
    getTransactions: jest.fn().mockResolvedValue([
      { id: "tx-1", from: "btc", to: "eth", status: "finished", createdAt: Date.now(), updatedAt: Date.now() }
    ]),
  },
}));

jest.mock("../../clients/changelly-defi", () => ({
  changelyDefiClient: {
    getTokens: jest.fn().mockResolvedValue([{ address: "0x1", symbol: "USDC" }]),
    getQuote: jest.fn().mockResolvedValue({ route: "ok" }),
    getApproval: jest.fn().mockResolvedValue({ spender: "0xspender", amount: "1000" }),
    createSwap: jest.fn().mockResolvedValue({ intentId: "intent-1", status: "pending" }),
  },
}));

jest.mock("ioredis", () =>
  jest.fn().mockImplementation(() => ({
    defineCommand: jest.fn(),
    call: jest.fn(),
  }))
);

describe("Backend /v1 routes", () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    process.env["CHANGELLY_API_KEY"] = "test-key";
    process.env["CHANGELLY_API_SECRET"] = "test-secret";
    app = await buildApp();
  });

  afterAll(async () => {
    await app.close();
  });

  it("GET /v1/config", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/config", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/assets", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/assets", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/feature-flags", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/feature-flags", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/pairs", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/pairs?from=btc&to=eth", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/validate-address", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/validate-address",
      headers: { origin: "moz-extension://test" },
      payload: { address: "0xabc", currency: "eth" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/quote/floating", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/quote/floating",
      headers: { origin: "moz-extension://test" },
      payload: { from: "btc", to: "eth", amount: 0.1 },
    });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/quote/fixed", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/quote/fixed",
      headers: { origin: "moz-extension://test" },
      payload: { from: "btc", to: "eth", amountFrom: 0.1 },
    });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/swap floating", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/swap",
      headers: { origin: "moz-extension://test" },
      payload: { from: "btc", to: "eth", address: "0xabc", amount: 0.1, rateType: "floating" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/swap fixed", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/swap",
      headers: { origin: "moz-extension://test" },
      payload: { from: "btc", to: "eth", address: "0xabc", amount: 0.1, rateType: "fixed", rateId: "rid-1" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/swap/status", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/swap/status?id=tx-1", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/swap/detail", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/swap/detail?id=tx-1", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/history", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/history?limit=20&offset=0", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/defi/tokens", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/defi/tokens?chainId=1", headers: { origin: "moz-extension://test" } });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/defi/quote", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/defi/quote",
      headers: { origin: "moz-extension://test" },
      payload: {
        fromTokenAddress: "0x1",
        toTokenAddress: "0x2",
        amount: "1000000",
        chainId: 1,
        slippage: 0.5,
        walletAddress: "0xwallet",
      },
    });
    expect(res.statusCode).toBe(200);
  });

  it("GET /v1/defi/approval", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/v1/defi/approval?tokenAddress=0x1&amount=1000&walletAddress=0xwallet&chainId=1",
      headers: { origin: "moz-extension://test" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("POST /v1/defi/swap", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/defi/swap",
      headers: { origin: "moz-extension://test" },
      payload: { quoteId: "q1", walletAddress: "0xwallet" },
    });
    expect(res.statusCode).toBe(200);
  });
});
