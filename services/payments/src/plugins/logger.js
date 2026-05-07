import { createRequire } from 'module';
import { config } from '../config/index.js';

const require = createRequire(import.meta.url);

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
    base: {
      service: 'payments',
      env: config.env,
    },
    transport: prettyTransport ?? undefined,
  };
}
