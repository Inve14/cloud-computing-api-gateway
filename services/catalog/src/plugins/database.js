// Fastify plugin: PostgreSQL connection pools via node-postgres (pg).
//
// Decorates the Fastify instance with:
//   fastify.pg         — master pool (all writes + reads until replica routing is added)
//   fastify.pgReplica  — read-replica pool (available for future read routing)
//
// Both pools open connections lazily; connectivity is verified on GET /ready.
// Wrapped with fastify-plugin so decorators escape plugin encapsulation.

import fp from 'fastify-plugin';
import pg from 'pg';

const { Pool } = pg;

/**
 * @param {import('fastify').FastifyInstance} fastify
 * @param {{ master: import('pg').PoolConfig, replica: import('pg').PoolConfig }} options
 */
async function databasePlugin(fastify, options) {
  const master = new Pool(options.master);
  const replica = new Pool(options.replica);

  fastify.addHook('onClose', async () => {
    await Promise.all([master.end(), replica.end()]);
    fastify.log.info('Database pools closed');
  });

  fastify.decorate('pg', master);
  fastify.decorate('pgReplica', replica);

  fastify.log.info(
    { max: options.master.max, idleTimeoutMillis: options.master.idleTimeoutMillis },
    'Database pools initialised (master + replica)'
  );
}

export default fp(databasePlugin, {
  name: 'database',
  fastify: '4.x',
});
