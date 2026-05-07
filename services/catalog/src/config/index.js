// Centralised configuration module.
// Loads .env only in non-production environments, then validates and exports
// a typed config object. Throws early with a clear message if mandatory
// variables are missing — this prevents silent misconfigurations at startup.

import { config as loadDotenv } from 'dotenv';

if (process.env.NODE_ENV !== 'production') {
  // dotenv silently ignores a missing .env file, so this is safe to call
  // even when env vars are already injected (e.g., in Docker or CI).
  loadDotenv();
}

/**
 * Returns the value of an environment variable, throwing if it is absent.
 * @param {string} name
 * @returns {string}
 */
function getRequired(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}. ` +
        'Check .env.example for all required variables.'
    );
  }
  return value;
}

/**
 * Returns the value of an environment variable or a default.
 * @param {string} name
 * @param {string} defaultValue
 * @returns {string}
 */
function getOptional(name, defaultValue) {
  return process.env[name] ?? defaultValue;
}

/**
 * Resolves database connection config from DATABASE_URL (preferred) or
 * individual DB_* variables. Throws if neither is provided.
 * @returns {object} pg.Pool compatible connection config
 */
function resolveDatabaseConfig() {
  const url = process.env.DATABASE_URL;
  if (url) {
    return { connectionString: url };
  }

  // Fall back to individual connection parameters
  const host = getRequired('DB_HOST');
  const port = parseInt(getOptional('DB_PORT', '5432'), 10);
  const database = getRequired('DB_NAME');
  const user = getRequired('DB_USER');
  const password = getRequired('DB_PASSWORD');

  return { host, port, database, user, password };
}

export const config = {
  env: getOptional('NODE_ENV', 'development'),
  port: parseInt(getOptional('PORT', '3001'), 10),

  database: {
    ...resolveDatabaseConfig(),
    max: parseInt(getOptional('DB_POOL_MAX', '10'), 10),
    idleTimeoutMillis: parseInt(getOptional('DB_IDLE_TIMEOUT_MS', '30000'), 10),
    connectionTimeoutMillis: parseInt(
      getOptional('DB_CONNECTION_TIMEOUT_MS', '3000'),
      10
    ),
  },

  logging: {
    level: getOptional('LOG_LEVEL', 'info'),
  },

  jwt: {
    // Public key used to verify RS256 tokens issued by the Users service.
    // Leave empty to trigger ephemeral-key generation (tests / local dev only).
    publicKeyPath: getOptional('JWT_PUBLIC_KEY_PATH', ''),
  },
};
