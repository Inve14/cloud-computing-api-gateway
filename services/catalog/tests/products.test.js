// Product endpoint tests — Node built-in runner + Fastify inject().
// Tests that require a real PostgreSQL instance are marked t.skip.
//
// Run with: npm test

import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.DATABASE_URL ??= 'postgresql://test:test@localhost:5432/catalog_test';
process.env.LOG_LEVEL ??= 'silent';
process.env.NODE_ENV ??= 'test';

const { buildServer } = await import('../src/server.js');

const SEED_PRODUCT_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const NONEXISTENT_UUID = '00000000-0000-0000-0000-000000000000';
const SEED_CATEGORY_ID = '11111111-1111-1111-1111-111111111111';

// ---------------------------------------------------------------------------
// GET /api/v1/catalog/products — requires DB (seed data)
// ---------------------------------------------------------------------------
test.skip('GET /api/v1/catalog/products returns 200 with seed data', async () => {
  // Start catalog-db first: docker compose up -d catalog-db
  // then: DATABASE_URL=postgresql://catalog_user:catalog_dev_password@localhost:5432/catalog_db npm test
});

// ---------------------------------------------------------------------------
// GET /api/v1/catalog/products/:productId — UUID validation (no DB needed)
// ---------------------------------------------------------------------------
test('GET /api/v1/catalog/products/:invalid-uuid returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'GET',
    url: '/api/v1/catalog/products/not-a-uuid',
  });

  assert.equal(response.statusCode, 400);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 400);
  assert.equal(body.title, 'VALIDATION_ERROR');
  assert.ok(body.type.startsWith('urn:catalog:error:'));
});

// ---------------------------------------------------------------------------
// GET /api/v1/catalog/products/:productId — 404 requires DB
// ---------------------------------------------------------------------------
test.skip('GET /api/v1/catalog/products/:nonexistent-uuid returns 404', async () => {
  // Requires a running PostgreSQL instance.
  // UUID used: 00000000-0000-0000-0000-000000000000 (not in seed data)
});

// ---------------------------------------------------------------------------
// POST /api/v1/catalog/products — auth middleware (no DB needed)
// ---------------------------------------------------------------------------
test('POST /api/v1/catalog/products without X-User-Role returns 401', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  // Body passes schema validation so the auth preHandler is reached.
  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/catalog/products',
    payload: {
      category_id: SEED_CATEGORY_ID,
      name: 'Test Product',
      slug: 'test-product',
      description: 'A test product',
      price_cents: 100,
    },
    headers: { 'content-type': 'application/json' },
  });

  assert.equal(response.statusCode, 401);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 401);
  assert.equal(body.title, 'UNAUTHORIZED');
});

test('POST /api/v1/catalog/products with X-User-Role: customer returns 403', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/catalog/products',
    payload: {
      category_id: SEED_CATEGORY_ID,
      name: 'Test Product',
      slug: 'test-product',
      description: 'A test product',
      price_cents: 100,
    },
    headers: {
      'content-type': 'application/json',
      'x-user-role': 'customer',
    },
  });

  assert.equal(response.statusCode, 403);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 403);
  assert.equal(body.title, 'FORBIDDEN');
});

// ---------------------------------------------------------------------------
// POST /api/v1/catalog/products — body schema validation (no DB needed)
// ---------------------------------------------------------------------------
test('POST /api/v1/catalog/products with missing required fields returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/catalog/products',
    payload: { name: 'Only name' },
    headers: {
      'content-type': 'application/json',
      'x-user-role': 'admin',
    },
  });

  // Schema validation (missing required fields) fires before any DB call.
  assert.equal(response.statusCode, 400);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 400);
  assert.equal(body.title, 'VALIDATION_ERROR');
});

// ---------------------------------------------------------------------------
// PATCH /api/v1/catalog/products/:productId — empty body returns 400
// ---------------------------------------------------------------------------
test('PATCH /api/v1/catalog/products/:productId with empty body returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'PATCH',
    url: `/api/v1/catalog/products/${SEED_PRODUCT_ID}`,
    payload: {},
    headers: {
      'content-type': 'application/json',
      'x-user-role': 'admin',
    },
  });

  // minProperties: 1 in body schema rejects empty body.
  assert.equal(response.statusCode, 400);
});
