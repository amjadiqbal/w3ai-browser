import { z } from "zod";

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
  process.exit(1);
}

export const env = parsed.data;
