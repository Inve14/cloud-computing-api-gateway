// Fastify plugin: PostgreSQL connection pool via node-postgres (pg).
//
// Decorates the Fastify instance with `fastify.pg` (a pg.Pool), making the
// pool available to all route handlers. The pool is closed gracefully when
// Fastify shuts down.
//
// The plugin intentionally does NOT test the connection at startup: pg.Pool
// opens connections lazily, so registration always succeeds even when the DB
// is temporarily unreachable. Connectivity is verified on demand via GET /ready.
//
// Wrapped with fastify-plugin so the `fastify.pg` decorator escapes plugin
// encapsulation and is visible across the entire server instance.

import fp from 'fastify-plugin';
import pg from 'pg';

const { Pool } = pg;

/**
 * @param {import('fastify').FastifyInstance} fastify
 * @param {import('pg').PoolConfig} options  — passed from config.database
 */
async function databasePlugin(fastify, options) {
  const pool = new Pool(options);

  // Close all connections when the server shuts down.
  fastify.addHook('onClose', async () => {
    await pool.end();
    fastify.log.info('Database pool closed');
  });

  // Expose the pool to all plugins and routes registered after this one.
  fastify.decorate('pg', pool);

  fastify.log.info(
    { max: options.max, idleTimeoutMillis: options.idleTimeoutMillis },
    'Database pool initialised'
  );
}

export default fp(databasePlugin, {
  name: 'database',
  fastify: '4.x',
});
