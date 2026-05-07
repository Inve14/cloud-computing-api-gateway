// Auth endpoint tests — Node built-in runner + Fastify inject().
// Tests that require a running PostgreSQL instance are marked t.skip.
// Tests that only exercise schema validation or middleware run without a DB.
//
// Run with: npm test

import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.DATABASE_URL ??= 'postgresql://test:test@localhost:5432/users_test';
process.env.LOG_LEVEL ??= 'silent';
process.env.NODE_ENV ??= 'test';
// No JWT_PRIVATE_KEY_PATH → jwt plugin generates ephemeral keys (test-safe).

const { buildServer } = await import('../src/server.js');

// ---------------------------------------------------------------------------
// POST /api/v1/users/auth/register — schema validation (no DB)
// ---------------------------------------------------------------------------
test('POST /auth/register with missing required fields returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/users/auth/register',
    payload: { email: 'user@example.com' }, // missing password, first_name, last_name
    headers: { 'content-type': 'application/json' },
  });

  assert.equal(response.statusCode, 400);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 400);
  assert.equal(body.title, 'VALIDATION_ERROR');
});

test('POST /auth/register with short password returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/users/auth/register',
    payload: { email: 'user@example.com', password: 'short', first_name: 'A', last_name: 'B' },
    headers: { 'content-type': 'application/json' },
  });

  assert.equal(response.statusCode, 400);
});

// ---------------------------------------------------------------------------
// POST /api/v1/users/auth/login — schema validation (no DB)
// ---------------------------------------------------------------------------
test('POST /auth/login with missing password returns 400', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'POST',
    url: '/api/v1/users/auth/login',
    payload: { email: 'user@example.com' },
    headers: { 'content-type': 'application/json' },
  });

  assert.equal(response.statusCode, 400);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 400);
  assert.equal(body.title, 'VALIDATION_ERROR');
});

// ---------------------------------------------------------------------------
// GET /api/v1/users/me — auth middleware (no DB)
// ---------------------------------------------------------------------------
test('GET /me without Authorization header returns 401', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'GET',
    url: '/api/v1/users/me',
  });

  assert.equal(response.statusCode, 401);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 401);
  assert.equal(body.title, 'UNAUTHORIZED');
});

test('GET /me with malformed Bearer token returns 401', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({
    method: 'GET',
    url: '/api/v1/users/me',
    headers: { authorization: 'Bearer this.is.not.a.valid.jwt' },
  });

  assert.equal(response.statusCode, 401);
  const body = JSON.parse(response.body);
  assert.equal(body.status, 401);
  assert.equal(body.title, 'UNAUTHORIZED');
});

// ---------------------------------------------------------------------------
// Integration tests — require a running PostgreSQL instance
// ---------------------------------------------------------------------------
test.skip('POST /auth/register returns 201 with user data', async () => {
  // docker compose up -d users-db
  // DATABASE_URL=postgresql://users_user:users_dev_password@localhost:5432/users_db npm test
});

test.skip('POST /auth/register with duplicate email returns 409 EMAIL_ALREADY_EXISTS', async () => {
  // Seed email: customer@example.com
});

test.skip('POST /auth/login with wrong password returns 401 INVALID_CREDENTIALS', async () => {});

test.skip('POST /auth/login success returns 200 with access_token and refresh_token', async () => {});
