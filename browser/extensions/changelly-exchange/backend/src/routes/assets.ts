import type { FastifyInstance } from "fastify";
import { changelyExchangeClient } from "../clients/changelly-exchange";

export async function assetsRoute(app: FastifyInstance) {
  app.get("/v1/assets", async (_req, reply) => {
    const currencies = await changelyExchangeClient.getCurrenciesFull();
    return reply.send(currencies);
  });

  app.get("/v1/feature-flags", async (_req, reply) => {
    const fiatPublicKey = process.env["CHANGELLY_FIAT_API_PUBLIC_KEY"] || process.env["CHANGELLY_API_KEY"];
    const fiatPrivateKey = process.env["CHANGELLY_FIAT_API_PRIVATE_KEY"] || process.env["CHANGELLY_API_SECRET"];

    return reply.send({
      fiatEnabled: Boolean(fiatPublicKey && fiatPrivateKey),
      fixedRateEnabled: true,
      defiEnabled: false,
      maintenanceMode: false,
    });
  });
}
