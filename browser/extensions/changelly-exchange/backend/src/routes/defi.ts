import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { changelyDefiClient } from "../clients/changelly-defi";

const QuoteBody = z.object({
  fromTokenAddress: z.string().min(1),
  toTokenAddress: z.string().min(1),
  amount: z.string().min(1),
  chainId: z.number().int().positive(),
  slippage: z.number().min(0.01).max(50).default(0.5),
  walletAddress: z.string().min(1),
});

const ApprovalQuery = z.object({
  tokenAddress: z.string().min(1),
  amount: z.string().min(1),
  walletAddress: z.string().min(1),
  chainId: z.coerce.number().int().positive(),
});

export async function defiRoute(app: FastifyInstance) {
  app.get("/v1/defi/tokens", async (req: FastifyRequest, reply) => {
    const { chainId } = z.object({ chainId: z.coerce.number().int().positive() }).parse(req.query);
    const tokens = await changelyDefiClient.getTokens(chainId);
    return reply.send(tokens);
  });

  app.post("/v1/defi/quote", async (req: FastifyRequest, reply) => {
    const body = QuoteBody.parse(req.body);
    const result = await changelyDefiClient.getQuote(body);
    return reply.send(result);
  });

  app.get("/v1/defi/approval", async (req: FastifyRequest, reply) => {
    const params = ApprovalQuery.parse(req.query);
    const result = await changelyDefiClient.getApproval(params);
    return reply.send(result);
  });

  app.post("/v1/defi/swap", async (req: FastifyRequest, reply) => {
    const result = await changelyDefiClient.createSwap(req.body);
    return reply.send(result);
  });
}
