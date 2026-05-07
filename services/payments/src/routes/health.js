// GET /health   — liveness probe
// GET /ready    — readiness probe (database check)
// GET /metrics  — Prometheus metrics

async function healthRoutes(fastify) {
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
      service: 'payments',
      timestamp: new Date().toISOString(),
    })
  );

  fastify.get('/ready', async (request, reply) => {
    const checks = { database: 'ok' };

    try {
      await fastify.pg.query('SELECT 1');
    } catch (err) {
      fastify.log.warn({ err }, 'Readiness check: database unreachable');
      checks.database = 'error';

      return reply.status(503).send({
        status: 'not_ready',
        service: 'payments',
        checks,
      });
    }

    return {
      status: 'ready',
      service: 'payments',
      checks,
    };
  });

  fastify.get('/metrics', async (request, reply) => {
    const metrics = await fastify.metricsRegistry.metrics();
    return reply.type(fastify.metricsRegistry.contentType).send(metrics);
  });
}

export default healthRoutes;
