export async function create(pool, { id, user_id, token_hash, expires_at }) {
  const { rows } = await pool.query(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [id, user_id, token_hash, expires_at]
  );
  return rows[0];
}

// Returns the token row only if it has not expired.
export async function findById(pool, id) {
  const { rows } = await pool.query(
    'SELECT * FROM refresh_tokens WHERE id = $1 AND expires_at > NOW()',
    [id]
  );
  return rows[0] ?? null;
}

export async function deleteById(pool, id) {
  await pool.query('DELETE FROM refresh_tokens WHERE id = $1', [id]);
}

// Purge all expired tokens for a user (housekeeping, called on login).
export async function deleteExpiredForUser(pool, userId) {
  await pool.query(
    'DELETE FROM refresh_tokens WHERE user_id = $1 AND expires_at <= NOW()',
    [userId]
  );
}
