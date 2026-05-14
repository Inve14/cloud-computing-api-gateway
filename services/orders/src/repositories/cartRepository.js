const CART_COLS = `id, user_id, created_at, updated_at`;
const ITEM_COLS = `id, cart_id, product_id, quantity, product_name_snapshot, unit_price_cents_snapshot, added_at, updated_at`;

export async function findCartByUserId(pool, userId) {
  const { rows } = await pool.query(
    `SELECT ${CART_COLS} FROM carts WHERE user_id = $1`,
    [userId]
  );
  return rows[0] ?? null;
}

export async function createCart(pool, userId) {
  const { rows } = await pool.query(
    `INSERT INTO carts (user_id) VALUES ($1) RETURNING ${CART_COLS}`,
    [userId]
  );
  return rows[0];
}

export async function listItemsByCartId(pool, cartId) {
  const { rows } = await pool.query(
    `SELECT ${ITEM_COLS} FROM cart_items WHERE cart_id = $1 ORDER BY added_at ASC`,
    [cartId]
  );
  return rows;
}

// INSERT with ON CONFLICT increment. Uses xmax to distinguish insert vs update.
export async function upsertItem(pool, cartId, productId, quantity, productNameSnapshot, unitPriceCentsSnapshot) {
  const { rows } = await pool.query(
    `INSERT INTO cart_items (cart_id, product_id, quantity, product_name_snapshot, unit_price_cents_snapshot)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (cart_id, product_id)
     DO UPDATE SET
       quantity   = cart_items.quantity + EXCLUDED.quantity,
       updated_at = NOW()
     RETURNING ${ITEM_COLS}, (xmax::text::int > 0) AS was_updated`,
    [cartId, productId, quantity, productNameSnapshot, unitPriceCentsSnapshot]
  );
  const { was_updated, ...item } = rows[0];
  return { item, inserted: !was_updated };
}

export async function getItemWithOwner(pool, itemId) {
  const { rows } = await pool.query(
    `SELECT ci.id, ci.cart_id, ci.product_id, ci.quantity,
            ci.product_name_snapshot, ci.unit_price_cents_snapshot,
            ci.added_at, ci.updated_at,
            c.user_id
     FROM cart_items ci
     JOIN carts c ON c.id = ci.cart_id
     WHERE ci.id = $1`,
    [itemId]
  );
  return rows[0] ?? null;
}

export async function updateItemQuantity(pool, itemId, quantity) {
  const { rows } = await pool.query(
    `UPDATE cart_items SET quantity = $1 WHERE id = $2 RETURNING ${ITEM_COLS}`,
    [quantity, itemId]
  );
  return rows[0] ?? null;
}

export async function deleteItem(pool, itemId) {
  const { rows } = await pool.query(
    `DELETE FROM cart_items WHERE id = $1 RETURNING id`,
    [itemId]
  );
  return rows[0] ?? null;
}

export async function clearItemsByCartId(pool, cartId) {
  await pool.query(`DELETE FROM cart_items WHERE cart_id = $1`, [cartId]);
}
