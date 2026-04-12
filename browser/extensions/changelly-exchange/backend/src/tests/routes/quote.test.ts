import { buildApp } from "../../index";
import type { FastifyInstance } from "fastify";

jest.mock("../../clients/changelly-exchange", () => ({
  changelyExchangeClient: {
    getFixRateForAmount: jest.fn().mockResolvedValue({
      id: "rate-id-123",
      result: "0.0342",
      networkFee: "0.0001",
      max: 1,
      min: 0.01,
    }),
    getExchangeAmount: jest.fn().mockResolvedValue([
      { result: "0.0342", networkFee: "0.0001" }
    ]),
  },
}));

jest.mock("ioredis", () =>
  jest.fn().mockImplementation(() => ({
    defineCommand: jest.fn(),
    call: jest.fn(),
  }))
);

let app: FastifyInstance;

beforeAll(async () => {
  process.env["CHANGELLY_API_KEY"] = "test-key";
  process.env["CHANGELLY_API_SECRET"] = "test-secret";
  app = await buildApp();
});

afterAll(async () => {
  await app.close();
});

describe("POST /v1/quote/floating", () => {
  it("returns a floating rate quote", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/quote/floating",
      headers: { origin: "moz-extension://test-ext-id" },
      payload: { from: "btc", to: "eth", amount: 0.1 },
    });
    expect(res.statusCode).toBe(200);
  });

  it("rejects missing fields with 400", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/quote/floating",
      headers: { origin: "moz-extension://test-ext-id" },
      payload: { from: "btc" },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("POST /v1/quote/fixed", () => {
  it("returns a fixed rate quote", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/quote/fixed",
      headers: { origin: "moz-extension://test-ext-id" },
      payload: { from: "btc", to: "eth", amountFrom: 0.1 },
    });
    expect(res.statusCode).toBe(200);
  });
});
