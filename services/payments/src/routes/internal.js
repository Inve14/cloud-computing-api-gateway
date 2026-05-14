// Internal-only routes — reachable on the Docker network only (not via Kong).
// No authentication: network-level trust (Docker bridge).
//
// POST /internal/payments/process

import * as paymentService from '../services/paymentService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function internalPaymentRoutes(fastify) {
  fastify.post(
    '/process',
    {
      schema: {
        body: {
          type: 'object',
          required: ['order_id', 'user_id', 'amount_cents', 'currency', 'payment_method'],
          additionalProperties: false,
          properties: {
            order_id:          { type: 'string', pattern: UUID },
            user_id:           { type: 'string', pattern: UUID },
            amount_cents:      { type: 'integer', minimum: 1 },
            currency:          { type: 'string', minLength: 3, maxLength: 3 },
            payment_method:    { type: 'string', enum: ['credit_card', 'paypal', 'bank_transfer'] },
            card_number_last4: { type: 'string', minLength: 4, maxLength: 4 },
          },
        },
      },
    },
    async (request) =>
      paymentService.processPayment(fastify.pg, request.body, request.log)
  );
}

export default internalPaymentRoutes;
