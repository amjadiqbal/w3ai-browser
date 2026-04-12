/**
 * HMAC-SHA512 request signer for Changelly Exchange API v2.
 * The secret NEVER leaves this module or the server process.
 */
import { createHmac } from "crypto";

export function signRequest(apiSecret: string, body: string): string {
  return createHmac("sha512", apiSecret).update(body).digest("hex");
}

export function buildHeaders(apiKey: string, apiSecret: string, body: string): Record<string, string> {
  const signature = signRequest(apiSecret, body);
  return {
    "Content-Type": "application/json",
    "api-key": apiKey,
    sign: signature,
  };
}
