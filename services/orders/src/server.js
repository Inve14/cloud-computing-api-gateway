import { fileURLToPath } from 'url';
import Fastify from 'fastify';

import { config } from './config/index.js';
import { buildLoggerConfig } from './plugins/logger.js';
import databasePlugin from './plugins/database.js';
import metricsPlugin from './plugins/metrics.js';
import jwtPlugin from './plugins/jwt.js';
import healthRoutes from './routes/health.js';
import cartRoutes from './routes/cart.js';
import orderRoutes from './routes/orders.js';
import { AppError, toProblem } from './errors.js';

export async function buildServer() {
  const server = Fastify({
    logger: buildLoggerConfig(),
  });

  // RFC 7807 error handler.
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

  await server.register(databasePlugin, config.database);

  // RS256 JWT — must be registered before any route that calls jwtVerify.
  await server.register(jwtPlugin);

  await server.register(metricsPlugin);
  await server.register(healthRoutes);
  await server.register(cartRoutes, { prefix: '/api/v1/cart' });
  await server.register(orderRoutes, { prefix: '/api/v1/orders' });

  return server;
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url);

if (isMain) {
  let server;

  try {
    server = await buildServer();
  } catch (err) {
    console.error({ err, msg: 'Failed to build server' });
    process.exit(1);
  }

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
