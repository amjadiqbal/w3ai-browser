import type { FastifyInstance } from "fastify";
import { changelyExchangeClient } from "../clients/changelly-exchange";

export async function assetsRoute(app: FastifyInstance) {
  app.get("/v1/assets", async (_req, reply) => {
    const currencies = await changelyExchangeClient.getCurrenciesFull();
    return reply.send(currencies);
  });

  app.get("/v1/feature-flags", async (_req, reply) => {
    return reply.send({
      fixedRateEnabled: true,
      defiSwapEnabled: false,
      maintenanceMode: false,
    });
  });
}
