import { authenticate } from '../middleware/auth.js';
import * as orderService from '../services/orderService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function orderRoutes(fastify) {
  fastify.addHook('preHandler', authenticate);

  // ------------------------------------------------------------------
  // GET /api/v1/orders
  // ------------------------------------------------------------------
  fastify.get(
    '/',
    {
      schema: {
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            page:    { type: 'integer', minimum: 1, default: 1 },
            limit:   { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            status:  { type: 'string', enum: ['pending', 'paid', 'shipped', 'delivered', 'cancelled'] },
            user_id: { type: 'string', pattern: UUID },
          },
        },
      },
    },
    async (request) =>
      orderService.listOrders(
        fastify.pg,
        request.user.sub,
        request.user.role,
        request.query
      )
  );

  // ------------------------------------------------------------------
  // GET /api/v1/orders/:orderId
  // ------------------------------------------------------------------
  fastify.get(
    '/:orderId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['orderId'],
          properties: { orderId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request) =>
      orderService.getOrder(
        fastify.pg,
        request.params.orderId,
        request.user.sub,
        request.user.role
      )
  );
}

export default orderRoutes;
