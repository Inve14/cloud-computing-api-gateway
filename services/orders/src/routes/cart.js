import { authenticate } from '../middleware/auth.js';
import * as cartService from '../services/cartService.js';
import * as orderService from '../services/orderService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function cartRoutes(fastify) {
  fastify.addHook('preHandler', authenticate);

  // ------------------------------------------------------------------
  // GET /api/v1/cart
  // ------------------------------------------------------------------
  fastify.get('/', async (request) =>
    cartService.getCart(fastify.pg, request.user.sub)
  );

  // ------------------------------------------------------------------
  // POST /api/v1/cart/items
  // ------------------------------------------------------------------
  fastify.post(
    '/items',
    {
      schema: {
        body: {
          type: 'object',
          required: ['product_id', 'quantity', 'product_name_snapshot', 'unit_price_cents_snapshot'],
          additionalProperties: false,
          properties: {
            product_id:                 { type: 'string', pattern: UUID },
            quantity:                   { type: 'integer', minimum: 1 },
            product_name_snapshot:      { type: 'string', minLength: 1, maxLength: 200 },
            unit_price_cents_snapshot:  { type: 'integer', minimum: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      const { data, inserted } = await cartService.addItem(
        fastify.pg,
        request.user.sub,
        request.body
      );
      return reply.status(inserted ? 201 : 200).send({ data });
    }
  );

  // ------------------------------------------------------------------
  // PATCH /api/v1/cart/items/:itemId
  // ------------------------------------------------------------------
  fastify.patch(
    '/items/:itemId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['itemId'],
          properties: { itemId: { type: 'string', pattern: UUID } },
        },
        body: {
          type: 'object',
          required: ['quantity'],
          additionalProperties: false,
          properties: {
            quantity: { type: 'integer', minimum: 1 },
          },
        },
      },
    },
    async (request) =>
      cartService.updateItem(
        fastify.pg,
        request.user.sub,
        request.params.itemId,
        request.body.quantity
      )
  );

  // ------------------------------------------------------------------
  // DELETE /api/v1/cart/items/:itemId
  // ------------------------------------------------------------------
  fastify.delete(
    '/items/:itemId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['itemId'],
          properties: { itemId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request, reply) => {
      await cartService.removeItem(
        fastify.pg,
        request.user.sub,
        request.params.itemId
      );
      return reply.status(204).send();
    }
  );

  // ------------------------------------------------------------------
  // DELETE /api/v1/cart
  // ------------------------------------------------------------------
  fastify.delete('/', async (request, reply) => {
    await cartService.clearCart(fastify.pg, request.user.sub);
    return reply.status(204).send();
  });

  // ------------------------------------------------------------------
  // POST /api/v1/cart/checkout
  // ------------------------------------------------------------------
  fastify.post(
    '/checkout',
    {
      schema: {
        body: {
          type: 'object',
          required: ['shipping_address', 'payment'],
          additionalProperties: false,
          properties: {
            shipping_address: {
              type: 'object',
              required: ['street', 'city', 'zip_code', 'country'],
              additionalProperties: false,
              properties: {
                street:   { type: 'string', minLength: 1, maxLength: 200 },
                city:     { type: 'string', minLength: 1, maxLength: 100 },
                zip_code: { type: 'string', minLength: 1, maxLength: 20 },
                country:  { type: 'string', minLength: 2, maxLength: 3 },
              },
            },
            payment: {
              type: 'object',
              required: ['method'],
              additionalProperties: false,
              properties: {
                method:            { type: 'string', enum: ['credit_card', 'paypal', 'bank_transfer'] },
                card_number_last4: { type: 'string', minLength: 4, maxLength: 4 },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const result = await orderService.checkout(fastify.pg, request.user.sub, request.body);
      return reply.status(201).send(result);
    }
  );
}

export default cartRoutes;
