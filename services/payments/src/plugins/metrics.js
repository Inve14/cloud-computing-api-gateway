import fp from 'fastify-plugin';
import { Registry, collectDefaultMetrics, Histogram } from 'prom-client';

async function metricsPlugin(fastify) {
  const registry = new Registry();

  collectDefaultMetrics({ register: registry });

  const httpRequestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
    registers: [registry],
  });

  fastify.addHook('onResponse', async (request, reply) => {
    const route = request.routeOptions?.url ?? 'unknown';
    httpRequestDuration
      .labels(request.method, route, String(reply.statusCode))
      .observe(reply.elapsedTime / 1000);
  });

  fastify.decorate('metricsRegistry', registry);
}

export default fp(metricsPlugin, {
  name: 'metrics',
  fastify: '4.x',
});
