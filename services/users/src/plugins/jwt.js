// Registers @fastify/jwt with RS256 asymmetric signing.
//
// Keys are read from filesystem paths set by JWT_PRIVATE_KEY_PATH and
// JWT_PUBLIC_KEY_PATH. When those env vars are absent (tests / local dev
// without mounted keys), ephemeral RSA keys are generated at startup.
// NEVER rely on ephemeral keys in production.

import fp from 'fastify-plugin';
import fastifyJwt from '@fastify/jwt';
import { readFileSync } from 'fs';
import { generateKeyPairSync } from 'crypto';
import { config } from '../config/index.js';

async function jwtPlugin(fastify) {
  let privateKey, publicKey;

  if (config.jwt.privateKeyPath && config.jwt.publicKeyPath) {
    privateKey = readFileSync(config.jwt.privateKeyPath);
    publicKey  = readFileSync(config.jwt.publicKeyPath);
  } else {
    // Ephemeral keys — test / dev only.
    fastify.log.warn('JWT key paths not configured — generating ephemeral RSA-2048 keys (NOT for production)');
    const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
    privateKey = pair.privateKey.export({ type: 'pkcs8', format: 'pem' });
    publicKey  = pair.publicKey.export({ type: 'spki',  format: 'pem' });
  }

  await fastify.register(fastifyJwt, {
    secret: { private: privateKey, public: publicKey },
    sign:   { algorithm: 'RS256', expiresIn: config.jwt.accessTtlSec },
    verify: { algorithms: ['RS256'] },
  });
}

export default fp(jwtPlugin, { name: 'jwt', fastify: '4.x' });
