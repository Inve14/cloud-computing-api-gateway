import fp from 'fastify-plugin';
import pg from 'pg';

const { Pool } = pg;

async function databasePlugin(fastify, options) {
  const pool = new Pool(options);

  fastify.addHook('onClose', async () => {
    await pool.end();
    fastify.log.info('Database pool closed');
  });

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
