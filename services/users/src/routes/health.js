// Health and observability routes.
//
// GET /health   — liveness probe (always 200 if the process is up)
// GET /ready    — readiness probe (200 only if PostgreSQL responds to SELECT 1)
// GET /metrics  — Prometheus metrics in text exposition format
//
// Kong and Docker both use these endpoints:
//   - /health  → Docker HEALTHCHECK and Kong active health-check
//   - /ready   → `depends_on: condition: service_healthy` in docker-compose
//   - /metrics → Prometheus scrape target

/**
 * @param {import('fastify').FastifyInstance} fastify
 */
async function healthRoutes(fastify) {
  // ------------------------------------------------------------------
  // GET /health — liveness probe
  // Does NOT check any dependencies; responds 200 as long as the process
  // is alive. A failing liveness probe causes the container to restart.
  // ------------------------------------------------------------------
  fastify.get(
    '/health',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string' },
              service: { type: 'string' },
              timestamp: { type: 'string', format: 'date-time' },
            },
            required: ['status', 'service', 'timestamp'],
          },
        },
      },
    },
    async () => ({
      status: 'ok',
      service: 'users',
      timestamp: new Date().toISOString(),
    })
  );

  // ------------------------------------------------------------------
  // GET /ready — readiness probe
  // Checks that the database is reachable. Returns 503 if not, so that
  // the load balancer / Consul stops routing traffic here until the
  // service is fully initialised.
  // ------------------------------------------------------------------
  fastify.get('/ready', async (request, reply) => {
    const checks = { database: 'ok' };

    try {
      await fastify.pg.query('SELECT 1');
    } catch (err) {
      fastify.log.warn({ err }, 'Readiness check: database unreachable');
      checks.database = 'error';

      return reply.status(503).send({
        status: 'not_ready',
        service: 'users',
        checks,
      });
    }

    return {
      status: 'ready',
      service: 'users',
      checks,
    };
  });

  // ------------------------------------------------------------------
  // GET /metrics — Prometheus exposition
  // Served on the main port (same as all other routes) to keep the Docker
  // network setup simple. Kong is configured to NOT proxy /metrics to
  // external clients.
  // ------------------------------------------------------------------
  fastify.get('/metrics', async (request, reply) => {
    const metrics = await fastify.metricsRegistry.metrics();
    return reply.type(fastify.metricsRegistry.contentType).send(metrics);
  });
}

export default healthRoutes;
