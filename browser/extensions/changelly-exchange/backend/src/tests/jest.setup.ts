process.env["NODE_ENV"] = "test";
process.env["CHANGELLY_API_KEY"] = process.env["CHANGELLY_API_KEY"] || "test-key";
process.env["CHANGELLY_API_SECRET"] = process.env["CHANGELLY_API_SECRET"] || "test-secret";
process.env["CHANGELLY_FIAT_API_PUBLIC_KEY"] = process.env["CHANGELLY_FIAT_API_PUBLIC_KEY"] || "fiat-public-key";
process.env["CHANGELLY_FIAT_API_PRIVATE_KEY"] = process.env["CHANGELLY_FIAT_API_PRIVATE_KEY"] || Buffer.from("-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----").toString("base64");
