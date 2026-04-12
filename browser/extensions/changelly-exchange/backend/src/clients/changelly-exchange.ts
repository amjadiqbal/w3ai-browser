/**
 * Low-level Changelly Exchange API v2 client.
 * All requests are HMAC-signed here — callers do not touch credentials.
 */
import { buildHeaders } from "../security/changelly-signer";
import { env } from "../env";

interface JsonRpcPayload {
  jsonrpc: "2.0";
  id: string;
  method: string;
  params: unknown;
}

async function call<T>(method: string, params: unknown = {}): Promise<T> {
  const id = crypto.randomUUID();
  const body: JsonRpcPayload = { jsonrpc: "2.0", id, method, params };
  const bodyStr = JSON.stringify(body);
  const headers = buildHeaders(env.CHANGELLY_API_KEY, env.CHANGELLY_API_SECRET, bodyStr);

  const resp = await fetch(env.CHANGELLY_API_BASE_URL, {
    method: "POST",
    headers,
    body: bodyStr,
    signal: AbortSignal.timeout(15_000),
  });

  if (!resp.ok) {
    throw new Error(`Changelly API HTTP ${resp.status}: ${resp.statusText}`);
  }

  const json = await resp.json() as { result?: T; error?: { code: number; message: string } };

  if (json.error) {
    const err = new Error(json.error.message) as NodeJS.ErrnoException & { code?: number };
    err.code = json.error.code;
    throw err;
  }

  return json.result as T;
}

export const changelyExchangeClient = {
  getCurrencies: () => call<unknown[]>("getCurrencies", { active: true }),
  getCurrenciesFull: () => call<unknown[]>("getCurrenciesFull", { active: true }),
  getPairsParams: (from: string, to: string) =>
    call<unknown>("getPairsParams", [{ from, to }]),
  getExchangeAmount: (params: { from: string; to: string; amount: number }) =>
    call<unknown>("getExchangeAmount", [params]),
  getFixRateForAmount: (params: { from: string; to: string; amountFrom: number }) =>
    call<unknown>("getFixRateForAmount", [params]),
  validateAddress: (currency: string, address: string, extraId?: string) =>
    call<unknown>("validateAddress", { currency, address, extraId }),
  createTransaction: (params: {
    from: string;
    to: string;
    address: string;
    amount: number;
    extraId?: string;
    refundAddress?: string;
  }) => call<unknown>("createTransaction", params),
  createFixTransaction: (params: {
    from: string;
    to: string;
    address: string;
    amountFrom: number;
    rateId: string;
    extraId?: string;
    refundAddress?: string;
  }) => call<unknown>("createFixTransaction", params),
  getTransactions: (params: { id?: string; limit?: number; offset?: number }) =>
    call<unknown[]>("getTransactions", params),
  getStatus: (id: string) => call<string>("getStatus", { id }),
};
