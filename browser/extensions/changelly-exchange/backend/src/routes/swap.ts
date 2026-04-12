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

export async function swapRoute(app: FastifyInstance) {
  app.post("/v1/swap", async (req: FastifyRequest, reply) => {
    const body = CreateSwapBody.parse(req.body);

    let result: unknown;
    if (body.rateType === "fixed") {
      if (!body.rateId) throw new Error("rateId is required for fixed-rate swaps");
      const fixedReq: {
        from: string;
        to: string;
        address: string;
        amountFrom: number;
        rateId: string;
        extraId?: string;
        refundAddress?: string;
      } = {
        from: body.from,
        to: body.to,
        address: body.address,
        amountFrom: body.amount,
        rateId: body.rateId,
      };
      if (body.extraId) fixedReq.extraId = body.extraId;
      if (body.refundAddress) fixedReq.refundAddress = body.refundAddress;

      result = await changelyExchangeClient.createFixTransaction(fixedReq);
    } else {
      const floatingReq: {
        from: string;
        to: string;
        address: string;
        amount: number;
        extraId?: string;
        refundAddress?: string;
      } = {
        from: body.from,
        to: body.to,
        address: body.address,
        amount: body.amount,
      };
      if (body.extraId) floatingReq.extraId = body.extraId;
      if (body.refundAddress) floatingReq.refundAddress = body.refundAddress;

      result = await changelyExchangeClient.createTransaction(floatingReq);
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

}
