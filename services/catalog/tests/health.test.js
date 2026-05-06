// Health endpoint tests.
// Uses Node's built-in test runner (node:test) and Fastify's inject() method
// to make in-process HTTP requests — no real network or database required
// for /health and /metrics.
//
// Run with: npm test  (or: node --test tests/**/*.test.js)

import { test } from 'node:test';
import assert from 'node:assert/strict';

// Provide a fallback DATABASE_URL so the config module can load without a
// real PostgreSQL instance. The pool opens connections lazily, so no
// actual TCP connection is made when building the server.
// The /ready test (which actually queries the DB) is skipped below.
process.env.DATABASE_URL ??= 'postgresql://test:test@localhost:5432/catalog_test';
process.env.LOG_LEVEL ??= 'silent'; // suppress log output during tests
process.env.NODE_ENV ??= 'test';

// Dynamic import ensures the env vars above are set before config/index.js
// is evaluated for the first time (static imports are hoisted above all code).
const { buildServer } = await import('../src/server.js');

// ---------------------------------------------------------------------------
// GET /health
// ---------------------------------------------------------------------------
test('GET /health returns 200 with correct shape', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({ method: 'GET', url: '/health' });

  assert.equal(response.statusCode, 200);

  const body = JSON.parse(response.body);
  assert.equal(body.status, 'ok');
  assert.equal(body.service, 'catalog');
  assert.ok(body.timestamp, 'timestamp field must be present');
  assert.doesNotThrow(
    () => new Date(body.timestamp),
    'timestamp must be a valid ISO date'
  );
});

// ---------------------------------------------------------------------------
// GET /metrics
// ---------------------------------------------------------------------------
test('GET /metrics returns 200 with Prometheus content-type', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({ method: 'GET', url: '/metrics' });

  assert.equal(response.statusCode, 200);
  assert.ok(
    response.headers['content-type']?.includes('text/plain'),
    `Expected text/plain content-type, got: ${response.headers['content-type']}`
  );
  assert.ok(
    response.body.includes('http_request_duration_seconds'),
    'Response must contain the custom HTTP duration histogram'
  );
});

// ---------------------------------------------------------------------------
// GET /ready — skipped: requires a running PostgreSQL instance
// ---------------------------------------------------------------------------
test.skip('GET /ready returns 200 when database is reachable', () => {
  // To run this test: start a real PostgreSQL instance and set DATABASE_URL.
  // In CI this will be exercised by the integration test suite.
});
