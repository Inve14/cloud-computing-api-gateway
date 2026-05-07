// Admin-only product routes — require X-User-Role: admin header (stub auth).
// POST   /api/v1/catalog/products
// PATCH  /api/v1/catalog/products/:productId
// PATCH  /api/v1/catalog/products/:productId/stock

import { requireAdmin } from '../middleware/auth.js';
import * as productService from '../services/productService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function adminRoutes(fastify) {
  // Apply requireAdmin to every route registered in this plugin scope.
  fastify.addHook('preHandler', requireAdmin);

  // ------------------------------------------------------------------
  // POST /products — create a new product + stock record
  // ------------------------------------------------------------------
  fastify.post(
    '/products',
    {
      schema: {
        body: {
          type: 'object',
          required: ['category_id', 'name', 'slug', 'description', 'price_cents'],
          additionalProperties: false,
          properties: {
            category_id:   { type: 'string', pattern: UUID },
            name:          { type: 'string', minLength: 1, maxLength: 200 },
            slug:          { type: 'string', minLength: 1, maxLength: 200 },
            description:   { type: 'string', minLength: 1 },
            price_cents:   { type: 'integer', minimum: 1 },
            currency:      { type: 'string', minLength: 3, maxLength: 3 },
            image_url:     { type: 'string', maxLength: 500 },
            initial_stock: { type: 'integer', minimum: 0, default: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      const result = await productService.createProduct(fastify.pg, request.body);
      return reply.status(201).send(result);
    }
  );

  // ------------------------------------------------------------------
  // PATCH /products/:productId — partial update; at least one field required
  // ------------------------------------------------------------------
  fastify.patch(
    '/products/:productId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['productId'],
          properties: { productId: { type: 'string', pattern: UUID } },
        },
        body: {
          type: 'object',
          minProperties: 1,
          additionalProperties: false,
          properties: {
            category_id:  { type: 'string', pattern: UUID },
            name:         { type: 'string', minLength: 1, maxLength: 200 },
            slug:         { type: 'string', minLength: 1, maxLength: 200 },
            description:  { type: 'string', minLength: 1 },
            price_cents:  { type: 'integer', minimum: 1 },
            currency:     { type: 'string', minLength: 3, maxLength: 3 },
            image_url:    { type: 'string', maxLength: 500 },
            is_active:    { type: 'boolean' },
          },
        },
      },
    },
    async (request) =>
      productService.updateProduct(fastify.pg, request.params.productId, request.body)
  );

  // ------------------------------------------------------------------
  // PATCH /products/:productId/stock — absolute restock / correction
  // ------------------------------------------------------------------
  fastify.patch(
    '/products/:productId/stock',
    {
      schema: {
        params: {
          type: 'object',
          required: ['productId'],
          properties: { productId: { type: 'string', pattern: UUID } },
        },
        body: {
          type: 'object',
          required: ['quantity_available'],
          additionalProperties: false,
          properties: {
            quantity_available: { type: 'integer', minimum: 0 },
          },
        },
      },
    },
    async (request) =>
      productService.setStock(fastify.pg, request.params.productId, request.body.quantity_available)
  );
}

export default adminRoutes;
