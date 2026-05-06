// Returns a Pino logger configuration object suitable for passing directly
// to the Fastify constructor's `logger` option.
//
// In development: pretty-printed output via pino-pretty (install as devDep).
// In all other environments: structured JSON — required for log aggregators
// (CloudWatch, Loki, etc.) to parse fields reliably.

import { config } from '../config/index.js';

/**
 * @returns {import('fastify').FastifyServerOptions['logger']}
 */
export function buildLoggerConfig() {
  const isDevelopment = config.env === 'development';

  return {
    level: config.logging.level,

    // Inject service-level fields into every log entry.
    base: {
      service: 'catalog',
      env: config.env,
    },

    // pino-pretty is a devDependency; only enable in development.
    // In production this field must be undefined (not null) so Fastify
    // does not attempt to load the transport.
    transport: isDevelopment
      ? {
          target: 'pino-pretty',
          options: { colorize: true, translateTime: 'SYS:standard' },
        }
      : undefined,
  };
}
