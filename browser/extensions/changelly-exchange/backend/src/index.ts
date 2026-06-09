import "dotenv/config";
import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import Redis from "ioredis";

import { configRoute } from "./routes/config";
import { assetsRoute } from "./routes/assets";
import { pairsRoute } from "./routes/pairs";
import { quoteRoute } from "./routes/quote";
import { swapRoute } from "./routes/swap";
import { defiRoute } from "./routes/defi";
import { historyRoute } from "./routes/history";
import { fiatRoute } from "./routes/fiat";
import { errorHandler } from "./middleware/error-handler";
import { env } from "./env";

const redis = new Redis(env.REDIS_URL);

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === "production" ? "info" : "debug",
    },
    disableRequestLogging: false,
    trustProxy: env.NODE_ENV === "production",
  });

  await app.register(helmet, {
    contentSecurityPolicy: false,
  });

  await app.register(cors, {
    origin: (origin, done) => {
      if (!origin) {
        done(null, false);
        return;
      }
      // Allow only moz-extension:// scheme origins (W3Ai extension)
      if (origin.startsWith("moz-extension://")) {
        done(null, true);
      } else {
        done(new Error("CORS: origin not allowed"), false);
      }
    },
    methods: ["GET", "POST"],
    allowedHeaders: ["Content-Type", "X-Request-Nonce"],
    credentials: false,
  });

  await app.register(rateLimit, {
    max: env.RATE_LIMIT_MAX,
    timeWindow: env.RATE_LIMIT_WINDOW_MS,
    ...(env.NODE_ENV === "test" ? {} : { redis }),
    keyGenerator: (req) => req.ip,
  });

  app.setErrorHandler(errorHandler);

  // Routes
  await configRoute(app);
  await assetsRoute(app);
  await pairsRoute(app);
  await quoteRoute(app);
  await swapRoute(app);
  await defiRoute(app);
  await historyRoute(app);
  await fiatRoute(app);

  return app;
}

if (require.main === module) {
  buildApp().then((app) => {
    app.listen({ host: env.HOST, port: env.PORT }, (err) => {
      if (err) {
        app.log.error(err);
        process.exit(1);
      }
    });
  });
}
