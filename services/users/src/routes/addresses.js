// Address routes — all require JWT authentication.
// GET    /api/v1/users/me/addresses
// POST   /api/v1/users/me/addresses
// GET    /api/v1/users/me/addresses/:addressId
// PATCH  /api/v1/users/me/addresses/:addressId
// DELETE /api/v1/users/me/addresses/:addressId

import { authenticate } from '../middleware/authenticate.js';
import * as addressService from '../services/addressService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function addressRoutes(fastify) {
  fastify.addHook('preHandler', authenticate);

  // ------------------------------------------------------------------
  // GET /me/addresses
  // ------------------------------------------------------------------
  fastify.get('/me/addresses', async (request) =>
    addressService.listAddresses(fastify.pg, request.user.sub)
  );

  // ------------------------------------------------------------------
  // POST /me/addresses
  // ------------------------------------------------------------------
  fastify.post(
    '/me/addresses',
    {
      schema: {
        body: {
          type: 'object',
          required: ['type', 'street', 'city', 'zip_code'],
          additionalProperties: false,
          properties: {
            type:       { type: 'string', enum: ['shipping', 'billing'] },
            street:     { type: 'string', minLength: 1, maxLength: 200 },
            city:       { type: 'string', minLength: 1, maxLength: 100 },
            zip_code:   { type: 'string', minLength: 1, maxLength: 20 },
            country:    { type: 'string', minLength: 2, maxLength: 2 },
            is_default: { type: 'boolean' },
          },
        },
      },
    },
    async (request, reply) => {
      const result = await addressService.createAddress(fastify.pg, request.user.sub, request.body);
      return reply.status(201).send(result);
    }
  );

  // ------------------------------------------------------------------
  // GET /me/addresses/:addressId
  // ------------------------------------------------------------------
  fastify.get(
    '/me/addresses/:addressId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['addressId'],
          properties: { addressId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request) =>
      addressService.getAddress(fastify.pg, request.params.addressId, request.user.sub)
  );

  // ------------------------------------------------------------------
  // PATCH /me/addresses/:addressId
  // ------------------------------------------------------------------
  fastify.patch(
    '/me/addresses/:addressId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['addressId'],
          properties: { addressId: { type: 'string', pattern: UUID } },
        },
        body: {
          type: 'object',
          minProperties: 1,
          additionalProperties: false,
          properties: {
            street:     { type: 'string', minLength: 1, maxLength: 200 },
            city:       { type: 'string', minLength: 1, maxLength: 100 },
            zip_code:   { type: 'string', minLength: 1, maxLength: 20 },
            country:    { type: 'string', minLength: 2, maxLength: 2 },
            is_default: { type: 'boolean' },
          },
        },
      },
    },
    async (request) =>
      addressService.updateAddress(
        fastify.pg,
        request.params.addressId,
        request.user.sub,
        request.body
      )
  );

  // ------------------------------------------------------------------
  // DELETE /me/addresses/:addressId
  // ------------------------------------------------------------------
  fastify.delete(
    '/me/addresses/:addressId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['addressId'],
          properties: { addressId: { type: 'string', pattern: UUID } },
        },
      },
    },
    async (request, reply) => {
      await addressService.deleteAddress(
        fastify.pg,
        request.params.addressId,
        request.user.sub
      );
      return reply.status(204).send();
    }
  );
}

export default addressRoutes;
