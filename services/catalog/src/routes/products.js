// Public product routes — no auth required.
// GET /api/v1/catalog/products
// GET /api/v1/catalog/products/:productId

import * as productService from '../services/productService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function productRoutes(fastify) {
  fastify.get(
    '/products',
    {
      schema: {
        querystring: {
          type: 'object',
          properties: {
            page:     { type: 'integer', minimum: 1, default: 1 },
            limit:    { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            category: { type: 'string' },
            q:        { type: 'string' },
            sort: {
              type: 'string',
              enum: ['created_at_desc', 'price_asc', 'price_desc'],
              default: 'created_at_desc',
            },
          },
        },
      },
    },
    async (request) => productService.listProducts(fastify.pg, request.query)
  );

  fastify.get(
    '/products/:productId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['productId'],
          properties: {
            productId: { type: 'string', pattern: UUID },
          },
        },
      },
    },
    async (request) => productService.getProduct(fastify.pg, request.params.productId)
  );
}

export default productRoutes;
