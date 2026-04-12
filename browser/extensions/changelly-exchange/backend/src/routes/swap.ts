import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { changelyExchangeClient } from "../clients/changelly-exchange";

const CreateSwapBody = z.object({
  from: z.string().min(1),
  to: z.string().min(1),
  address: z.string().min(1),
  amount: z.number().positive(),
  extraId: z.string().optional(),
  refundAddress: z.string().optional(),
  rateType: z.enum(["floating", "fixed"]),
  rateId: z.string().optional(),
});

const SwapStatusQuery = z.object({ id: z.string().min(1) });
const HistoryQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  id: z.string().optional(),
});

export async function swapRoute(app: FastifyInstance) {
  app.post("/v1/swap", async (req: FastifyRequest, reply) => {
    const body = CreateSwapBody.parse(req.body);

    let result: unknown;
    if (body.rateType === "fixed") {
      if (!body.rateId) throw new Error("rateId is required for fixed-rate swaps");
      result = await changelyExchangeClient.createFixTransaction({
        from: body.from,
        to: body.to,
        address: body.address,
        amountFrom: body.amount,
        rateId: body.rateId,
        extraId: body.extraId,
        refundAddress: body.refundAddress,
      });
    } else {
      result = await changelyExchangeClient.createTransaction({
        from: body.from,
        to: body.to,
        address: body.address,
        amount: body.amount,
        extraId: body.extraId,
        refundAddress: body.refundAddress,
      });
    }

    return reply.send(result);
  });

  app.get("/v1/swap/status", async (req: FastifyRequest, reply) => {
    const { id } = SwapStatusQuery.parse(req.query);
    const status = await changelyExchangeClient.getStatus(id);
    return reply.send({ id, status });
  });

  app.get("/v1/swap/detail", async (req: FastifyRequest, reply) => {
    const { id } = SwapStatusQuery.parse(req.query);
    const transactions = await changelyExchangeClient.getTransactions({ id, limit: 1 });
    return reply.send(transactions[0] ?? null);
  });

  app.get("/v1/history", async (req: FastifyRequest, reply) => {
    const { limit, offset } = HistoryQuery.parse(req.query);
    const transactions = await changelyExchangeClient.getTransactions({ limit, offset });
    return reply.send(transactions);
  });
}
