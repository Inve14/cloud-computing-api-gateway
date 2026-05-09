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
      service: 'catalog',
      timestamp: new Date().toISOString(),
    })
  );

  // ------------------------------------------------------------------
  // GET /ready — readiness probe
  // Checks both master and replica. Returns 503 if either is down.
  // ------------------------------------------------------------------
  fastify.get('/ready', async (request, reply) => {
    const checks = {
      database_master: 'ok',
      database_replica: 'ok',
    };

    const [masterResult, replicaResult] = await Promise.allSettled([
      fastify.pg.query('SELECT 1'),
      fastify.pgReplica.query('SELECT 1'),
    ]);

    if (masterResult.status === 'rejected') {
      fastify.log.warn({ err: masterResult.reason }, 'Readiness check: master unreachable');
      checks.database_master = 'error';
    }
    if (replicaResult.status === 'rejected') {
      fastify.log.warn({ err: replicaResult.reason }, 'Readiness check: replica unreachable');
      checks.database_replica = 'error';
    }

    const allOk = checks.database_master === 'ok' && checks.database_replica === 'ok';

    if (!allOk) {
      return reply.status(503).send({
        status: 'not_ready',
        service: 'catalog',
        checks,
      });
    }

    return {
      status: 'ready',
      service: 'catalog',
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
