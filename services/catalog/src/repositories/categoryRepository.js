export async function listCategories(pool) {
  const { rows } = await pool.query(
    `SELECT id, name, slug, description, created_at, updated_at
     FROM categories
     ORDER BY name ASC`
  );
  return rows;
}

export async function getCategoryById(pool, id) {
  const { rows } = await pool.query(
    `SELECT id, name, slug, description, created_at, updated_at
     FROM categories
     WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}
