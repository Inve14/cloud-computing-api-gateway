// Users service entry point.
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
import healthRoutes from './routes/health.js';

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

  // Database pool — registered first so routes can reference fastify.pg.
  await server.register(databasePlugin, config.database);

  // Prometheus metrics — registers onResponse hook and exposes the registry.
  await server.register(metricsPlugin);

  // Health, readiness, and metrics routes.
  await server.register(healthRoutes);

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
