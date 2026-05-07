// JWT plugin for the Catalog service — verify-only (no signing).
//
// In production, only the public key is loaded from JWT_PUBLIC_KEY_PATH.
// The private key is never needed here: the Users service signs tokens,
// Catalog only verifies them.
//
// When JWT_PUBLIC_KEY_PATH is absent (tests / local dev without mounted
// volumes), an ephemeral RSA pair is generated so that tests can call
// fastify.jwt.sign() to produce valid tokens without a running Users service.
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
    // Verify-only: no private key.
  } else {
    fastify.log.warn(
      'JWT_PUBLIC_KEY_PATH not set — generating ephemeral RSA-2048 keys (test only, NOT for production)'
    );
    const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
    privateKey = pair.privateKey.export({ type: 'pkcs8', format: 'pem' });
    publicKey  = pair.publicKey.export({ type: 'spki',  format: 'pem' });
  }

  await fastify.register(fastifyJwt, {
    // Provide private key only in ephemeral/test mode so tests can sign tokens.
    secret: privateKey
      ? { private: privateKey, public: publicKey }
      : { public: publicKey },
    sign:   { algorithm: 'RS256' },
    verify: { algorithms: ['RS256'] },
  });
}

export default fp(jwtPlugin, { name: 'jwt', fastify: '4.x' });
