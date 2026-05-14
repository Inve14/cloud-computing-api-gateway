// Protected profile routes.
// GET   /api/v1/users/me
// PATCH /api/v1/users/me

import { authenticate } from '../middleware/authenticate.js';
import * as userService from '../services/userService.js';

async function meRoutes(fastify) {
  fastify.get(
    '/me',
    { preHandler: authenticate },
    async (request) => userService.getMe(fastify.pg, request.user.sub)
  );

  fastify.patch(
    '/me',
    {
      preHandler: authenticate,
      schema: {
        body: {
          type: 'object',
          minProperties: 1,
          additionalProperties: false,
          properties: {
            first_name: { type: 'string', minLength: 1, maxLength: 100 },
            last_name:  { type: 'string', minLength: 1, maxLength: 100 },
            phone:      { type: 'string', maxLength: 20 },
          },
        },
      },
    },
    async (request) => userService.updateMe(fastify.pg, request.user.sub, request.body)
  );
}

export default meRoutes;
