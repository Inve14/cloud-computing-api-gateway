// Protected profile route.
// GET /api/v1/users/me

import { authenticate } from '../middleware/authenticate.js';
import * as userService from '../services/userService.js';

async function meRoutes(fastify) {
  fastify.get(
    '/me',
    { preHandler: authenticate },
    async (request) => userService.getMe(fastify.pg, request.user.sub)
  );
}

export default meRoutes;
