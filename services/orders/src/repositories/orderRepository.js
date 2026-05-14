const ORDER_COLS = `id, user_id, status, total_cents, currency, shipping_address, payment_id, created_at, updated_at`;
const ITEM_COLS  = `id, order_id, product_id, product_name, quantity, price_cents, subtotal_cents`;

export async function createOrderWithItems(pool, { userId, totalCents, currency, shippingAddress, items }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [order] } = await client.query(
      `INSERT INTO orders (user_id, status, total_cents, currency, shipping_address)
       VALUES ($1, 'pending', $2, $3, $4)
       RETURNING ${ORDER_COLS}`,
      [userId, totalCents, currency, JSON.stringify(shippingAddress)]
    );

    const orderItems = [];
    for (const item of items) {
      const { rows: [orderItem] } = await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, quantity, price_cents, subtotal_cents)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING ${ITEM_COLS}`,
        [order.id, item.product_id, item.product_name, item.quantity, item.price_cents, item.subtotal_cents]
      );
      orderItems.push(orderItem);
    }

    await client.query('COMMIT');
    return { order, items: orderItems };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function findOrderWithItems(pool, orderId) {
  const { rows: [order] } = await pool.query(
    `SELECT ${ORDER_COLS} FROM orders WHERE id = $1`,
    [orderId]
  );
  if (!order) return null;

  const { rows: items } = await pool.query(
    `SELECT ${ITEM_COLS} FROM order_items WHERE order_id = $1`,
    [orderId]
  );

  return { order, items };
}

export async function list(pool, { userId, page, limit, status }) {
  const offset = (page - 1) * limit;
  const conditions = [];
  const values = [];
  let idx = 1;

  if (userId) {
    conditions.push(`user_id = $${idx++}`);
    values.push(userId);
  }
  if (status) {
    conditions.push(`status = $${idx++}`);
    values.push(status);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const { rows: [{ total }] } = await pool.query(
    `SELECT COUNT(*) AS total FROM orders ${where}`,
    values
  );

  const limitIdx = idx++;
  const offsetIdx = idx++;
  const { rows } = await pool.query(
    `SELECT ${ORDER_COLS} FROM orders ${where} ORDER BY created_at DESC LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
    [...values, limit, offset]
  );

  return { rows, total: parseInt(total, 10) };
}

export async function updateOrderStatus(pool, orderId, status, paymentId = null) {
  const { rows: [order] } = await pool.query(
    `UPDATE orders
     SET status = $1, payment_id = COALESCE($2::uuid, payment_id)
     WHERE id = $3
     RETURNING ${ORDER_COLS}`,
    [status, paymentId, orderId]
  );
  return order;
}
