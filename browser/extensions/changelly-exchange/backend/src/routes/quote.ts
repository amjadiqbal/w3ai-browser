import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { changelyExchangeClient } from "../clients/changelly-exchange";

const FloatingQuoteBody = z.object({
  from: z.string().min(1),
  to: z.string().min(1),
  amount: z.number().positive(),
});

const FixedQuoteBody = z.object({
  from: z.string().min(1),
  to: z.string().min(1),
  amountFrom: z.number().positive(),
});

export async function quoteRoute(app: FastifyInstance) {
  app.post("/v1/quote/floating", async (req: FastifyRequest, reply) => {
    const body = FloatingQuoteBody.parse(req.body);
    const result = await changelyExchangeClient.getExchangeAmount(body);
    return reply.send(result);
  });

  app.post("/v1/quote/fixed", async (req: FastifyRequest, reply) => {
    const body = FixedQuoteBody.parse(req.body);
    const result = await changelyExchangeClient.getFixRateForAmount(body);
    return reply.send(result);
  });
}
