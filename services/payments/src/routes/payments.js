import { authenticate, requireAdmin } from '../middleware/auth.js';
import * as paymentService from '../services/paymentService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function paymentRoutes(fastify) {
  // ------------------------------------------------------------------
  // GET /api/v1/payments/:paymentId
  // ------------------------------------------------------------------
  fastify.get(
    '/:paymentId',
    {
      preHandler: authenticate,
      schema: {
        params: {
          type: 'object',
          required: ['paymentId'],
          properties: { paymentId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request) =>
      paymentService.getPayment(
        fastify.pg,
        request.params.paymentId,
        request.user.sub,
        request.user.role
      )
  );

  // ------------------------------------------------------------------
  // GET /api/v1/payments
  // ------------------------------------------------------------------
  fastify.get(
    '/',
    {
      preHandler: authenticate,
      schema: {
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: {
            page:     { type: 'integer', minimum: 1, default: 1 },
            limit:    { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            status:   { type: 'string', enum: ['pending', 'completed', 'failed', 'refunded'] },
            order_id: { type: 'string', pattern: UUID },
            user_id:  { type: 'string', pattern: UUID },
          },
        },
      },
    },
    async (request) =>
      paymentService.listPayments(
        fastify.pg,
        request.user.sub,
        request.user.role,
        request.query
      )
  );

  // ------------------------------------------------------------------
  // POST /api/v1/payments/:paymentId/refund  (admin only)
  // ------------------------------------------------------------------
  fastify.post(
    '/:paymentId/refund',
    {
      preHandler: requireAdmin,
      schema: {
        params: {
          type: 'object',
          required: ['paymentId'],
          properties: { paymentId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request) =>
      paymentService.refundPayment(fastify.pg, request.params.paymentId, request.log)
  );
}

export default paymentRoutes;
