// Public category routes — no auth required.
// GET /api/v1/catalog/categories
// GET /api/v1/catalog/categories/:categoryId

import * as categoryService from '../services/categoryService.js';

const UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

async function categoryRoutes(fastify) {
  fastify.get('/categories', async () => {
    const categories = await categoryService.listCategories(fastify.pg);
    return { data: categories };
  });

  fastify.get(
    '/categories/:categoryId',
    {
      schema: {
        params: {
          type: 'object',
          required: ['categoryId'],
          properties: {
            categoryId: { type: 'string', pattern: UUID },
          },
        },
      },
    },
    async (request) => {
      const category = await categoryService.getCategoryById(fastify.pg, request.params.categoryId);
      return { data: category };
    }
  );
}

export default categoryRoutes;
