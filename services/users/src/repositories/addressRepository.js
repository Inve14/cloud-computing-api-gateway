const COLS = `id, user_id, type, street, city, zip_code, country, is_default, created_at, updated_at`;

export async function listByUserId(pool, userId) {
  const { rows } = await pool.query(
    `SELECT ${COLS} FROM addresses WHERE user_id = $1 ORDER BY created_at ASC`,
    [userId]
  );
  return rows;
}

export async function getById(pool, id) {
  const { rows } = await pool.query(
    `SELECT ${COLS} FROM addresses WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function create(pool, { userId, type, street, city, zip_code, country, is_default }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (is_default) {
      await client.query(
        `UPDATE addresses SET is_default = FALSE WHERE user_id = $1 AND type = $2`,
        [userId, type]
      );
    }
    const { rows } = await client.query(
      `INSERT INTO addresses (user_id, type, street, city, zip_code, country, is_default)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING ${COLS}`,
      [userId, type, street, city, zip_code, country, is_default]
    );
    await client.query('COMMIT');
    return rows[0];
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function update(pool, { id, userId, fields, addressType }) {
  if (fields.is_default === true) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `UPDATE addresses SET is_default = FALSE WHERE user_id = $1 AND type = $2 AND id != $3`,
        [userId, addressType, id]
      );
      const keys = Object.keys(fields);
      const values = Object.values(fields);
      const set = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
      const { rows } = await client.query(
        `UPDATE addresses SET ${set} WHERE id = $${keys.length + 1} RETURNING ${COLS}`,
        [...values, id]
      );
      await client.query('COMMIT');
      return rows[0] ?? null;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  const keys = Object.keys(fields);
  const values = Object.values(fields);
  const set = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
  const { rows } = await pool.query(
    `UPDATE addresses SET ${set} WHERE id = $${keys.length + 1} RETURNING ${COLS}`,
    [...values, id]
  );
  return rows[0] ?? null;
}

export async function remove(pool, id) {
  const { rows } = await pool.query(
    `DELETE FROM addresses WHERE id = $1 RETURNING id`,
    [id]
  );
  return rows[0] ?? null;
}
