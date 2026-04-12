import type { FastifyInstance } from "fastify";

export async function configRoute(app: FastifyInstance) {
  app.get("/v1/config", async (_req, reply) => {
    return reply.send({
      proxyVersion: "v1",
      environment: process.env["NODE_ENV"] ?? "production",
      termsUrl: "https://changelly.com/terms-of-service",
      privacyUrl: "https://changelly.com/privacy",
      changellySupportUrl: "https://support.changelly.com",
      maintenanceMode: false,
    });
  });
}
