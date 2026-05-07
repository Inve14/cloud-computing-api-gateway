import { fileURLToPath } from 'url';
import Fastify from 'fastify';

import { config } from './config/index.js';
import { buildLoggerConfig } from './plugins/logger.js';
import databasePlugin from './plugins/database.js';
import metricsPlugin from './plugins/metrics.js';
import healthRoutes from './routes/health.js';

export async function buildServer() {
  const server = Fastify({
    logger: buildLoggerConfig(),
  });

  await server.register(databasePlugin, config.database);
  await server.register(metricsPlugin);
  await server.register(healthRoutes);

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
