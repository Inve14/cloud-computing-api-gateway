// Returns a Pino logger configuration object suitable for passing directly
// to the Fastify constructor's `logger` option.
//
// In development: pretty-printed output via pino-pretty (install as devDep).
// In all other environments: structured JSON — required for log aggregators
// (CloudWatch, Loki, etc.) to parse fields reliably.

import { createRequire } from 'module';
import { config } from '../config/index.js';

const require = createRequire(import.meta.url);

/**
 * @returns {import('fastify').FastifyServerOptions['logger']}
 */
export function buildLoggerConfig() {
  let prettyTransport = null;

  if (config.env === 'development') {
    try {
      require.resolve('pino-pretty');
      prettyTransport = {
        target: 'pino-pretty',
        options: { colorize: true, translateTime: 'SYS:standard' },
      };
    } catch {
      console.warn('[logger] pino-pretty not installed, using JSON logging');
    }
  }

  return {
    level: config.logging.level,

    // Inject service-level fields into every log entry.
    base: {
      service: 'catalog',
      env: config.env,
    },

    // prettyTransport is only set when NODE_ENV=development AND pino-pretty
    // is resolvable. Falls back to JSON logging otherwise (including inside
    // Docker where pino-pretty is omitted via --omit=dev).
    transport: prettyTransport ?? undefined,
  };
}
