// Fastify plugin: Prometheus metrics via prom-client.
//
// Registers:
//   - Default Node.js metrics (heap, event loop lag, GC, active handles, …)
//   - A custom histogram: http_request_duration_seconds
//     Labels: method, route, status_code
//
// Each response triggers the onResponse hook which records the request
// duration. The metric data is exposed on GET /metrics (implemented in
// routes/health.js for consistency with the other health routes).
//
// Uses a dedicated Registry instance (not the global default) so that
// multiple server instances in the same process (e.g. during tests) do
// not share or double-register metrics.

import fp from 'fastify-plugin';
import { Registry, collectDefaultMetrics, Histogram } from 'prom-client';

/**
 * @param {import('fastify').FastifyInstance} fastify
 */
async function metricsPlugin(fastify) {
  const registry = new Registry();

  collectDefaultMetrics({ register: registry });

  const httpRequestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    // Buckets tuned for a low-latency internal service (values in seconds).
    buckets: [0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
    registers: [registry],
  });

  // Record duration for every response.
  // `reply.elapsedTime` is the number of milliseconds since the request
  // was received, provided by Fastify automatically.
  fastify.addHook('onResponse', async (request, reply) => {
    const route = request.routeOptions?.url ?? 'unknown';
    httpRequestDuration
      .labels(request.method, route, String(reply.statusCode))
      .observe(reply.elapsedTime / 1000);
  });

  // Expose the registry so the /metrics route can call registry.metrics().
  fastify.decorate('metricsRegistry', registry);
}

export default fp(metricsPlugin, {
  name: 'metrics',
  fastify: '4.x',
});
