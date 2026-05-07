// Auth routes — no authentication required.
// POST /api/v1/users/auth/register
// POST /api/v1/users/auth/login
// POST /api/v1/users/auth/refresh
// POST /api/v1/users/auth/logout  (requires Bearer token to identify the user)

import { authenticate } from '../middleware/authenticate.js';
import * as authService from '../services/authService.js';

// Basic email pattern (full RFC 5321 validation happens at DB UNIQUE constraint level).
const EMAIL = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';

async function authRoutes(fastify) {
  // ------------------------------------------------------------------
  // POST /auth/register
  // ------------------------------------------------------------------
  fastify.post(
    '/auth/register',
    {
      schema: {
        body: {
          type: 'object',
          required: ['email', 'password', 'first_name', 'last_name'],
          additionalProperties: false,
          properties: {
            email:      { type: 'string', maxLength: 254, pattern: EMAIL },
            password:   { type: 'string', minLength: 8 },
            first_name: { type: 'string', minLength: 1, maxLength: 100 },
            last_name:  { type: 'string', minLength: 1, maxLength: 100 },
            phone:      { type: 'string', maxLength: 20 },
          },
        },
      },
    },
    async (request, reply) => {
      const user = await authService.register(fastify.pg, request.body);
      return reply.status(201).send({ data: user });
    }
  );

  // ------------------------------------------------------------------
  // POST /auth/login
  // ------------------------------------------------------------------
  fastify.post(
    '/auth/login',
    {
      schema: {
        body: {
          type: 'object',
          required: ['email', 'password'],
          additionalProperties: false,
          properties: {
            email:    { type: 'string', maxLength: 254 },
            password: { type: 'string', minLength: 1 },
          },
        },
      },
    },
    async (request) => {
      // Pass fastify.jwt.sign so the service can mint tokens without
      // importing fastify directly.
      return authService.login(fastify.pg, fastify.jwt.sign.bind(fastify.jwt), request.body);
    }
  );

  // ------------------------------------------------------------------
  // POST /auth/refresh
  // ------------------------------------------------------------------
  fastify.post(
    '/auth/refresh',
    {
      schema: {
        body: {
          type: 'object',
          required: ['refresh_token'],
          additionalProperties: false,
          properties: {
            refresh_token: { type: 'string', minLength: 1 },
          },
        },
      },
    },
    async (request) =>
      authService.refresh(fastify.pg, fastify.jwt.sign.bind(fastify.jwt), request.body)
  );

  // ------------------------------------------------------------------
  // POST /auth/logout — requires a valid access token to identify the user
  // ------------------------------------------------------------------
  fastify.post(
    '/auth/logout',
    {
      preHandler: authenticate,
      schema: {
        body: {
          type: 'object',
          required: ['refresh_token'],
          additionalProperties: false,
          properties: {
            refresh_token: { type: 'string', minLength: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      await authService.logout(fastify.pg, {
        refresh_token: request.body.refresh_token,
        userId: request.user.sub,
      });
      return reply.status(204).send();
    }
  );
}

export default authRoutes;
