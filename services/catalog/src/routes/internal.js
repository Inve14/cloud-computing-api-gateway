// Internal-only routes — reachable on the Docker network only (not via Kong).
// No authentication: network-level trust (Docker bridge).
//
// GET  /internal/catalog/products/:id
// POST /internal/catalog/stock/reserve
// POST /internal/catalog/stock/release

import * as productService from '../services/productService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

const stockBodySchema = {
  type: 'object',
  required: ['product_id', 'quantity'],
  additionalProperties: false,
  properties: {
    product_id: { type: 'string', pattern: UUID },
    quantity:   { type: 'integer', minimum: 1 },
  },
};

async function internalRoutes(fastify) {
  fastify.get(
    '/products/:id',
    {
      schema: {
        params: {
          type: 'object',
          required: ['id'],
          properties: { id: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request) => productService.getProductInternal(fastify.pg, request.params.id)
  );

  fastify.post(
    '/stock/reserve',
    { schema: { body: stockBodySchema } },
    async (request) =>
      productService.reserveStock(fastify.pg, request.body.product_id, request.body.quantity)
  );

  fastify.post(
    '/stock/release',
    { schema: { body: stockBodySchema } },
    async (request) =>
      productService.releaseStock(fastify.pg, request.body.product_id, request.body.quantity)
  );
}

export default internalRoutes;
