const SORT_MAP = {
  created_at_desc: 'p.created_at DESC',
  price_asc: 'p.price_cents ASC',
  price_desc: 'p.price_cents DESC',
};

// ---------- Read (public) ----------
// TODO: route read-only queries (listProducts, getProduct, listByIds) through
//       fastify.pgReplica once replica routing is validated end-to-end.

export async function listProducts(pool, { page, limit, category, q, sort }) {
  const offset = (page - 1) * limit;
  const order = SORT_MAP[sort] ?? 'p.created_at DESC';

  // Build dynamic filter — separate from pagination params so the count
  // query can reuse them without LIMIT / OFFSET.
  const fp = [];
  const conditions = ['p.is_active = true'];
  let joinCat = '';

  if (category) {
    joinCat = 'JOIN categories c ON c.id = p.category_id';
    fp.push(category);
    conditions.push(`c.slug = $${fp.length}`);
  }

  if (q) {
    fp.push(`%${q}%`);
    const i = fp.length;
    // $i can appear twice; PostgreSQL resolves the same param index correctly.
    conditions.push(`(p.name ILIKE $${i} OR p.description ILIKE $${i})`);
  }

  const where = 'WHERE ' + conditions.join(' AND ');

  const [{ rows: [countRow] }, { rows }] = await Promise.all([
    pool.query(
      `SELECT COUNT(*) AS total FROM products p ${joinCat} ${where}`,
      fp
    ),
    pool.query(
      `SELECT p.id, p.category_id, p.name, p.slug, p.description,
              p.price_cents, p.currency, p.image_url,
              COALESCE(ps.quantity_available, 0) AS quantity_available
       FROM products p
       ${joinCat}
       LEFT JOIN product_stock ps ON ps.product_id = p.id
       ${where}
       ORDER BY ${order}
       LIMIT $${fp.length + 1} OFFSET $${fp.length + 2}`,
      [...fp, limit, offset]
    ),
  ]);

  return { rows, total: parseInt(countRow.total, 10) };
}

export async function getProductById(pool, id) {
  const { rows } = await pool.query(
    `SELECT p.id, p.category_id, p.name, p.slug, p.description,
            p.price_cents, p.currency, p.image_url, p.is_active,
            p.created_at, p.updated_at,
            COALESCE(ps.quantity_available, 0) AS quantity_available
     FROM products p
     LEFT JOIN product_stock ps ON ps.product_id = p.id
     WHERE p.id = $1 AND p.is_active = true`,
    [id]
  );
  return rows[0] ?? null;
}

// Internal: returns inactive products too (orders service needs them for
// stale-item detection at checkout time).
export async function getProductByIdInternal(pool, id) {
  const { rows } = await pool.query(
    `SELECT p.id, p.name, p.price_cents, p.currency, p.is_active,
            COALESCE(ps.quantity_available, 0) AS quantity_available,
            COALESCE(ps.quantity_reserved,  0) AS quantity_reserved
     FROM products p
     LEFT JOIN product_stock ps ON ps.product_id = p.id
     WHERE p.id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

// Returns full product + stock fields (used after writes to build response).
export async function getProductWithStock(pool, id) {
  const { rows } = await pool.query(
    `SELECT p.id, p.category_id, p.name, p.slug, p.description,
            p.price_cents, p.currency, p.image_url, p.is_active,
            p.created_at, p.updated_at,
            COALESCE(ps.quantity_available, 0) AS quantity_available,
            COALESCE(ps.quantity_reserved,  0) AS quantity_reserved
     FROM products p
     LEFT JOIN product_stock ps ON ps.product_id = p.id
     WHERE p.id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function productExists(pool, id) {
  const { rows } = await pool.query(
    'SELECT 1 FROM products WHERE id = $1',
    [id]
  );
  return rows.length > 0;
}

// ---------- Write (admin / internal) ----------

export async function createProduct(pool, data) {
  const { category_id, name, slug, description, price_cents, currency, image_url, initial_stock } = data;

  // Transactional: product row + stock row must both succeed or neither.
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [product] } = await client.query(
      `INSERT INTO products (category_id, name, slug, description, price_cents, currency, image_url)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [category_id, name, slug, description, price_cents, currency ?? 'EUR', image_url ?? null]
    );

    const { rows: [stock] } = await client.query(
      `INSERT INTO product_stock (product_id, quantity_available, quantity_reserved)
       VALUES ($1, $2, 0)
       RETURNING *`,
      [product.id, initial_stock ?? 0]
    );

    await client.query('COMMIT');
    return { product, stock };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function updateProduct(pool, id, fields) {
  const ALLOWED = ['name', 'slug', 'description', 'price_cents', 'currency', 'image_url', 'is_active', 'category_id'];
  const setClauses = [];
  const params = [];

  for (const key of ALLOWED) {
    if (key in fields) {
      params.push(fields[key]);
      setClauses.push(`${key} = $${params.length}`);
    }
  }

  params.push(id);
  const { rows } = await pool.query(
    `UPDATE products SET ${setClauses.join(', ')} WHERE id = $${params.length} RETURNING *`,
    params
  );
  return rows[0] ?? null;
}

export async function setStock(pool, productId, quantityAvailable) {
  const { rows } = await pool.query(
    `UPDATE product_stock
     SET quantity_available = $1, last_restocked_at = NOW()
     WHERE product_id = $2
     RETURNING product_id, quantity_available, quantity_reserved, last_restocked_at, updated_at`,
    [quantityAvailable, productId]
  );
  return rows[0] ?? null;
}

// Atomic: decrements available, increments reserved in a single statement.
// Returns null when quantity_available < quantity (race-condition-safe).
export async function reserveStock(pool, productId, quantity) {
  const { rows } = await pool.query(
    `UPDATE product_stock
     SET quantity_available = quantity_available - $1,
         quantity_reserved  = quantity_reserved  + $1
     WHERE product_id = $2 AND quantity_available >= $1
     RETURNING product_id, quantity_available, quantity_reserved`,
    [quantity, productId]
  );
  return rows[0] ?? null;
}

// Atomic: decrements reserved, increments available in a single statement.
// Returns null when quantity_reserved < quantity.
export async function releaseStock(pool, productId, quantity) {
  const { rows } = await pool.query(
    `UPDATE product_stock
     SET quantity_available = quantity_available + $1,
         quantity_reserved  = quantity_reserved  - $1
     WHERE product_id = $2 AND quantity_reserved >= $1
     RETURNING product_id, quantity_available, quantity_reserved`,
    [quantity, productId]
  );
  return rows[0] ?? null;
}
