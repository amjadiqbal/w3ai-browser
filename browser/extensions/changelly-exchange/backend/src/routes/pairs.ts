import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { changelyExchangeClient } from "../clients/changelly-exchange";

const PairQuery = z.object({ from: z.string(), to: z.string() });
const ValidateBody = z.object({
  address: z.string().min(1),
  currency: z.string().min(1),
  extraId: z.string().optional(),
});

export async function pairsRoute(app: FastifyInstance) {
  app.get("/v1/pairs", async (req: FastifyRequest, reply) => {
    const { from, to } = PairQuery.parse(req.query);
    const result = await changelyExchangeClient.getPairsParams(from, to);
    return reply.send(result);
  });

  app.post("/v1/validate-address", async (req: FastifyRequest, reply) => {
    const { address, currency, extraId } = ValidateBody.parse(req.body);
    const result = await changelyExchangeClient.validateAddress(currency, address, extraId);
    return reply.send(result);
  });
}
