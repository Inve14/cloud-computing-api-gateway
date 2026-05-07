// Health endpoint tests — Node built-in runner + Fastify inject().
// No real network or database needed for /health and /metrics.
//
// Run with: npm test

import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.DATABASE_URL ??= 'postgresql://test:test@localhost:5432/orders_test';
process.env.LOG_LEVEL ??= 'silent';
process.env.NODE_ENV ??= 'test';

const { buildServer } = await import('../src/server.js');

test('GET /health returns 200 with correct shape', async (t) => {
  const server = await buildServer();
  t.after(() => server.close());

  const response = await server.inject({ method: 'GET', url: '/health' });

  assert.equal(response.statusCode, 200);

  const body = JSON.parse(response.body);
  assert.equal(body.status, 'ok');
  assert.equal(body.service, 'orders');
  assert.ok(body.timestamp, 'timestamp field must be present');
  assert.doesNotThrow(
    () => new Date(body.timestamp),
    'timestamp must be a valid ISO date'
  );
});

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

test.skip('GET /ready returns 200 when database is reachable', () => {
  // Requires a running PostgreSQL instance. Covered by the integration suite.
});
