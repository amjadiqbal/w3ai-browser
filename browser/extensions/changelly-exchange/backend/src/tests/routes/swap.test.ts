import { buildApp } from "../../index";
import type { FastifyInstance } from "fastify";

jest.mock("../../clients/changelly-exchange", () => ({
  changelyExchangeClient: {
    createTransaction: jest.fn().mockResolvedValue({
      id: "tx-abc-123",
      payinAddress: "1BtcDepositAddr",
      payoutAddress: "0xEthAddr",
      status: "new",
      amountExpectedFrom: 0.1,
      amountExpectedTo: 1.42,
    }),
    createFixTransaction: jest.fn().mockResolvedValue({
      id: "tx-fixed-456",
      payinAddress: "1BtcDepositAddr",
      payoutAddress: "0xEthAddr",
      status: "new",
    }),
    getStatus: jest.fn().mockResolvedValue("waiting"),
    getTransactions: jest.fn().mockResolvedValue([]),
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

describe("POST /v1/swap (floating)", () => {
  it("creates a floating-rate swap", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/swap",
      headers: { origin: "moz-extension://test" },
      payload: {
        from: "btc",
        to: "eth",
        address: "0xEthAddr",
        amount: 0.1,
        rateType: "floating",
      },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.id).toBe("tx-abc-123");
  });

  it("returns 400 for missing address", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/swap",
      headers: { origin: "moz-extension://test" },
      payload: { from: "btc", to: "eth", amount: 0.1, rateType: "floating" },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("GET /v1/swap/status", () => {
  it("returns status for a known transaction", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/v1/swap/status?id=tx-abc-123",
      headers: { origin: "moz-extension://test" },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.status).toBe("waiting");
  });
});
