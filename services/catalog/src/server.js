// Catalog service entry point.
//
// Exports `buildServer()` so tests can create a fully configured Fastify
// instance without starting the HTTP listener. The listener is started only
// when this file is executed directly (isMain check at the bottom).

import { fileURLToPath } from 'url';
import Fastify from 'fastify';

import { config } from './config/index.js';
import { buildLoggerConfig } from './plugins/logger.js';
import databasePlugin from './plugins/database.js';
import metricsPlugin from './plugins/metrics.js';
import jwtPlugin from './plugins/jwt.js';
import healthRoutes from './routes/health.js';
import productRoutes from './routes/products.js';
import categoryRoutes from './routes/categories.js';
import adminRoutes from './routes/admin.js';
import internalRoutes from './routes/internal.js';
import { AppError, toProblem } from './errors.js';

/**
 * Assembles and returns a configured Fastify instance.
 * Does NOT call server.listen() — callers decide when to start listening.
 *
 * @returns {Promise<import('fastify').FastifyInstance>}
 */
export async function buildServer() {
  const server = Fastify({
    logger: buildLoggerConfig(),
  });

  // RFC 7807 error handler — must be registered before plugins/routes so it
  // applies to all scopes. Handles AppError, Fastify schema validation errors,
  // and unexpected errors uniformly.
  server.setErrorHandler((err, request, reply) => {
    const cid = request.headers['x-correlation-id'] ?? null;

    if (err.validation) {
      return reply.status(400).send(toProblem(400, 'VALIDATION_ERROR', err.message, cid));
    }

    if (err instanceof AppError) {
      return reply.status(err.statusCode).send(toProblem(err.statusCode, err.code, err.detail, cid));
    }

    request.log.error({ err }, 'Unhandled error');
    return reply.status(500).send(toProblem(500, 'INTERNAL_ERROR', 'Unexpected server error', cid));
  });

  // Database pools — master (fastify.pg) and replica (fastify.pgReplica).
  await server.register(databasePlugin, {
    master: config.database,
    replica: config.databaseReplica,
  });

  // RS256 JWT — must be registered before any route that calls jwtVerify.
  await server.register(jwtPlugin);

  // Prometheus metrics — registers onResponse hook and exposes the registry.
  await server.register(metricsPlugin);

  // Health, readiness, and metrics routes.
  await server.register(healthRoutes);

  // Business routes
  await server.register(productRoutes,  { prefix: '/api/v1/catalog' });
  await server.register(categoryRoutes, { prefix: '/api/v1/catalog' });
  await server.register(adminRoutes,    { prefix: '/api/v1/catalog' });
  await server.register(internalRoutes, { prefix: '/internal/catalog' });

  return server;
}

// ---------------------------------------------------------------------------
// Start the server only when this module is the process entry point.
// When imported by tests or other modules, this block is skipped.
// ---------------------------------------------------------------------------
const isMain =
  process.argv[1] === fileURLToPath(import.meta.url);

if (isMain) {
  let server;

  try {
    server = await buildServer();
  } catch (err) {
    // Logger may not be available if buildServer threw before Fastify init.
    console.error({ err, msg: 'Failed to build server' });
    process.exit(1);
  }

  // Graceful shutdown: finish in-flight requests before exiting.
  const shutdown = async (signal) => {
    server.log.info({ signal }, 'Shutdown signal received — closing server');
    try {
      await server.close();
      process.exit(0);
    } catch (err) {
      server.log.error({ err }, 'Error during graceful shutdown');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  try {
    await server.listen({ port: config.port, host: '0.0.0.0' });
  } catch (err) {
    server.log.error({ err }, 'Failed to start HTTP listener');
    process.exit(1);
  }
}
