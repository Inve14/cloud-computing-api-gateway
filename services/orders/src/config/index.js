import { config as loadDotenv } from 'dotenv';

if (process.env.NODE_ENV !== 'production') {
  loadDotenv();
}

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

function getOptional(name, defaultValue) {
  return process.env[name] ?? defaultValue;
}

function resolveDatabaseConfig() {
  const url = process.env.DATABASE_URL;
  if (url) {
    return { connectionString: url };
  }

  return {
    host: getRequired('DB_HOST'),
    port: parseInt(getOptional('DB_PORT', '5432'), 10),
    database: getRequired('DB_NAME'),
    user: getRequired('DB_USER'),
    password: getRequired('DB_PASSWORD'),
  };
}

export const config = {
  env: getOptional('NODE_ENV', 'development'),
  port: parseInt(getOptional('PORT', '3003'), 10),

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
};
