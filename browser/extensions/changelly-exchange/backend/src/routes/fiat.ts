import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { changellyFiatClient } from "../clients/changelly-fiat";

const flowSchema = z.enum(["buy", "sell"]);

const offersQuerySchema = z.object({
  providerCode: z.string().optional(),
  externalUserID: z.string().optional(),
  currencyFrom: z.string().min(1),
  currencyTo: z.string().min(1),
  amountFrom: z.union([z.string(), z.number()]),
  country: z.string().length(2),
  state: z.string().optional(),
  ip: z.string().optional(),
  paymentMethodCode: z.string().optional(),
});

const baseOrderSchema = z.object({
  externalOrderId: z.string().min(1),
  externalUserId: z.string().min(1),
  providerCode: z.string().min(1),
  currencyFrom: z.string().min(1),
  currencyTo: z.string().min(1),
  amountFrom: z.union([z.string(), z.number()]),
  country: z.string().length(2),
  state: z.string().optional(),
  ip: z.string().optional(),
  paymentMethod: z.string().optional(),
  userAgent: z.string().optional(),
  metadata: z.record(z.unknown()).optional(),
});

const onRampOrderSchema = baseOrderSchema.extend({
  walletAddress: z.string().min(1),
  walletExtraId: z.string().optional(),
  returnSuccessUrl: z.string().url().optional(),
  returnFailedUrl: z.string().url().optional(),
});

const offRampOrderSchema = baseOrderSchema.extend({
  refundAddress: z.string().min(1),
});

const validateAddressSchema = z.object({
  currency: z.string().min(1),
  walletAddress: z.string().min(1),
  walletExtraId: z.string().optional(),
});

const ordersQuerySchema = z.object({
  startDate: z.string().optional(),
  endDate: z.string().optional(),
  orderId: z.union([z.string(), z.array(z.string())]).optional(),
  externalUserId: z.union([z.string(), z.array(z.string())]).optional(),
  externalOrderId: z.union([z.string(), z.array(z.string())]).optional(),
  status: z.union([z.string(), z.array(z.string())]).optional(),
  offset: z.coerce.number().min(0).optional(),
  limit: z.coerce.number().min(1).max(100).optional(),
});

function normalizeArrayQuery(value?: string | string[]) {
  if (!value) return undefined;
  return Array.isArray(value) ? value : [value];
}

export async function fiatRoute(app: FastifyInstance) {
  app.get("/v1/fiat/providers", async (_req, reply) => {
    const data = await changellyFiatClient.getProviders();
    return reply.send(data);
  });

  app.get("/v1/fiat/currencies", async (req, reply) => {
    const query = z
      .object({
        type: z.enum(["crypto", "fiat"]).optional(),
        providerCode: z.string().optional(),
        supportedFlow: flowSchema.optional(),
      })
      .parse(req.query);
    const data = await changellyFiatClient.getCurrencies(query);
    return reply.send(data);
  });

  app.get("/v1/fiat/countries", async (req, reply) => {
    const query = z
      .object({
        providerCode: z.string().optional(),
        supportedFlow: flowSchema.optional(),
      })
      .parse(req.query);
    const data = await changellyFiatClient.getCountries(query);
    return reply.send(data);
  });

  app.get("/v1/fiat/offers/on-ramp", async (req, reply) => {
    const query = offersQuerySchema.omit({ paymentMethodCode: true }).parse(req.query);
    const data = await changellyFiatClient.getOnRampOffers(query);
    return reply.send(data);
  });

  app.get("/v1/fiat/offers/off-ramp", async (req, reply) => {
    const query = offersQuerySchema.parse(req.query);
    const data = await changellyFiatClient.getOffRampOffers(query);
    return reply.send(data);
  });

  app.post("/v1/fiat/orders/on-ramp", async (req, reply) => {
    const payload = onRampOrderSchema.parse(req.body);
    const data = await changellyFiatClient.createOnRampOrder(payload);
    return reply.send(data);
  });

  app.post("/v1/fiat/orders/off-ramp", async (req, reply) => {
    const payload = offRampOrderSchema.parse(req.body);
    const data = await changellyFiatClient.createOffRampOrder(payload);
    return reply.send(data);
  });

  app.get("/v1/fiat/orders", async (req, reply) => {
    const query = ordersQuerySchema.parse(req.query);
    const data = await changellyFiatClient.getOrders({
      ...query,
      orderId: normalizeArrayQuery(query.orderId as string | string[] | undefined)?.join(","),
      externalUserId: normalizeArrayQuery(query.externalUserId as string | string[] | undefined)?.join(","),
      externalOrderId: normalizeArrayQuery(query.externalOrderId as string | string[] | undefined)?.join(","),
      status: normalizeArrayQuery(query.status as string | string[] | undefined)?.join(","),
    });
    return reply.send(data);
  });

  app.post("/v1/fiat/validate-address", async (req, reply) => {
    const payload = validateAddressSchema.parse(req.body);
    const data = await changellyFiatClient.validateAddress(payload);
    return reply.send(data);
  });
}
