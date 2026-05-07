// JWT plugin for the Payments service — verify-only (no signing).
//
// In production, only the public key is loaded from JWT_PUBLIC_KEY_PATH.
// When the env var is absent (tests / local dev), an ephemeral RSA pair is
// generated so tests can call fastify.jwt.sign() without a running Users service.
// NEVER run without real keys in production.

import fp from 'fastify-plugin';
import fastifyJwt from '@fastify/jwt';
import { readFileSync } from 'fs';
import { generateKeyPairSync } from 'crypto';
import { config } from '../config/index.js';

async function jwtPlugin(fastify) {
  let publicKey, privateKey;

  if (config.jwt.publicKeyPath) {
    publicKey = readFileSync(config.jwt.publicKeyPath);
  } else {
    fastify.log.warn(
      'JWT_PUBLIC_KEY_PATH not set — generating ephemeral RSA-2048 keys (test only, NOT for production)'
    );
    const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
    privateKey = pair.privateKey.export({ type: 'pkcs8', format: 'pem' });
    publicKey  = pair.publicKey.export({ type: 'spki',  format: 'pem' });
  }

  await fastify.register(fastifyJwt, {
    secret: privateKey
      ? { private: privateKey, public: publicKey }
      : { public: publicKey },
    sign:   { algorithm: 'RS256' },
    verify: { algorithms: ['RS256'] },
  });
}

export default fp(jwtPlugin, { name: 'jwt', fastify: '4.x' });
