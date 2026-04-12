import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";

export function errorHandler(
  err: FastifyError,
  _req: FastifyRequest,
  reply: FastifyReply
) {
  if (err instanceof ZodError) {
    return reply.status(400).send({
      error: "VALIDATION_ERROR",
      message: "Invalid request parameters.",
      issues: err.errors.map((e) => ({ path: e.path.join("."), message: e.message })),
    });
  }

  const statusCode = err.statusCode ?? 500;

  if (statusCode >= 500) {
    reply.log.error({ err }, "Internal server error");
  }

  return reply.status(statusCode).send({
    error: err.code ?? "INTERNAL_ERROR",
    message: statusCode < 500 ? err.message : "An internal error occurred.",
  });
}
