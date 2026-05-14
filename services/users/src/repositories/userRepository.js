const PUBLIC_COLS = `id, email, first_name, last_name, phone, role, is_verified, created_at, updated_at`;

export async function findByEmail(pool, email) {
  // Returns full row including password_hash for login verification.
  const { rows } = await pool.query(
    'SELECT * FROM users WHERE email = $1',
    [email]
  );
  return rows[0] ?? null;
}

export async function findById(pool, id) {
  const { rows } = await pool.query(
    `SELECT ${PUBLIC_COLS} FROM users WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function create(pool, { email, password_hash, first_name, last_name, phone }) {
  const { rows } = await pool.query(
    `INSERT INTO users (email, password_hash, first_name, last_name, phone)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING ${PUBLIC_COLS}`,
    [email, password_hash, first_name, last_name, phone ?? null]
  );
  return rows[0];
}

export async function updateById(pool, id, fields) {
  const keys = Object.keys(fields);
  const values = Object.values(fields);
  const set = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
  const { rows } = await pool.query(
    `UPDATE users SET ${set} WHERE id = $${keys.length + 1} RETURNING ${PUBLIC_COLS}`,
    [...values, id]
  );
  return rows[0] ?? null;
}
