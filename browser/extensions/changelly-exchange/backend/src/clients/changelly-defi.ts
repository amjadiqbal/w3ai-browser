/**
 * Changelly DeFi Swap API client.
 * Uses Bearer token authentication — secret stays server-side only.
 */
import { env } from "../env";

async function get<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${env.CHANGELLY_DEFI_BASE_URL}${path}`);
  if (params) {
    Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  }
  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${env.CHANGELLY_API_KEY}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!resp.ok) throw new Error(`Changelly DeFi API HTTP ${resp.status}`);
  return resp.json() as Promise<T>;
}

async function post<T>(path: string, body: unknown): Promise<T> {
  const resp = await fetch(`${env.CHANGELLY_DEFI_BASE_URL}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.CHANGELLY_API_KEY}`,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  if (!resp.ok) throw new Error(`Changelly DeFi API HTTP ${resp.status}`);
  return resp.json() as Promise<T>;
}

export const changelyDefiClient = {
  getTokens: (chainId: number) => get<unknown>("/tokens", { chainId: String(chainId) }),
  getQuote: (params: {
    fromTokenAddress: string;
    toTokenAddress: string;
    amount: string;
    chainId: number;
    slippage: number;
    walletAddress: string;
  }) => post<unknown>("/quote", params),
  getApproval: (params: { tokenAddress: string; amount: string; walletAddress: string; chainId: number }) =>
    get<unknown>("/approve/spender", {
      tokenAddress: params.tokenAddress,
      amount: params.amount,
      walletAddress: params.walletAddress,
      chainId: String(params.chainId),
    }),
  createSwap: (params: unknown) => post<unknown>("/swap", params),
};
