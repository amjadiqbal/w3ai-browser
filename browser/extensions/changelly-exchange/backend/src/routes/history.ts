import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { changelyExchangeClient } from "../clients/changelly-exchange";

const HistoryQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export async function historyRoute(app: FastifyInstance) {
  app.get("/v1/history", async (req: FastifyRequest, reply) => {
    const { limit, offset } = HistoryQuery.parse(req.query);
    const transactions = await changelyExchangeClient.getTransactions({ limit, offset });
    return reply.send(transactions);
  });
}
