import fs from "node:fs";
import path from "node:path";
import { config as loadDotenv } from "dotenv";
import { z } from "zod";

const dotenvCandidates = [
  process.env["CHANGELLY_ENV_FILE"],
  path.resolve(process.cwd(), ".env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, "../../.env"),
].filter((value): value is string => Boolean(value));

for (const filePath of dotenvCandidates) {
  if (fs.existsSync(filePath)) {
    loadDotenv({ path: filePath });
    break;
  }
}

const Schema = z.object({
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default("127.0.0.1"),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  CHANGELLY_API_KEY: z.string().min(1),
  CHANGELLY_API_SECRET: z.string().min(1),
  CHANGELLY_API_BASE_URL: z.string().url().default("https://api.changelly.com/v2"),
  CHANGELLY_DEFI_BASE_URL: z.string().url().default("https://dex-api.changelly.com/v1"),
  REDIS_URL: z.string().default("redis://localhost:6379"),
  DATABASE_URL: z.string().optional(),
  ALLOWED_ORIGINS: z.string().default("moz-extension://"),
  RATE_LIMIT_MAX: z.coerce.number().default(60),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60_000),
});

const parsed = Schema.safeParse(process.env);

if (!parsed.success) {
  console.error("Invalid environment configuration:\n", parsed.error.format());
  console.error("Checked .env paths:", dotenvCandidates.join(", "));
  console.error("Run: npm run env:setup (in backend/) and then fill CHANGELLY_API_KEY / CHANGELLY_API_SECRET.");
  process.exit(1);
}

export const env = parsed.data;
