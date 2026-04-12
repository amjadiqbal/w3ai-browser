import { signRequest, buildHeaders } from "../../src/security/changelly-signer";

describe("changelly-signer", () => {
  const SECRET = "test-secret-key-abc";
  const BODY = JSON.stringify({ jsonrpc: "2.0", id: "1", method: "getCurrencies", params: {} });

  it("produces a deterministic HMAC-SHA512 hex string", () => {
    const sig = signRequest(SECRET, BODY);
    expect(sig).toHaveLength(128); // SHA-512 hex = 128 chars
    expect(sig).toMatch(/^[0-9a-f]+$/);
  });

  it("is deterministic for same inputs", () => {
    expect(signRequest(SECRET, BODY)).toBe(signRequest(SECRET, BODY));
  });

  it("differs for different secrets", () => {
    expect(signRequest("secret-a", BODY)).not.toBe(signRequest("secret-b", BODY));
  });

  it("differs for different bodies", () => {
    expect(signRequest(SECRET, BODY)).not.toBe(signRequest(SECRET, BODY + "x"));
  });

  it("buildHeaders includes api-key and sign", () => {
    const headers = buildHeaders("my-api-key", SECRET, BODY);
    expect(headers["api-key"]).toBe("my-api-key");
    expect(headers["sign"]).toBe(signRequest(SECRET, BODY));
    expect(headers["Content-Type"]).toBe("application/json");
  });
});
