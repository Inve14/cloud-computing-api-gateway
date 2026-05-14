const COLS = `id, order_id, user_id, amount_cents, currency, payment_method, status, transaction_reference, failure_reason, created_at, updated_at`;

export async function findById(pool, id) {
  const { rows } = await pool.query(
    `SELECT ${COLS} FROM payments WHERE id = $1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function findByOrderId(pool, orderId) {
  const { rows } = await pool.query(
    `SELECT ${COLS} FROM payments WHERE order_id = $1`,
    [orderId]
  );
  return rows[0] ?? null;
}

export async function list(pool, { userId, page, limit, status, orderId }) {
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
  if (orderId) {
    conditions.push(`order_id = $${idx++}`);
    values.push(orderId);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const countResult = await pool.query(
    `SELECT COUNT(*) AS total FROM payments ${where}`,
    values
  );
  const total = parseInt(countResult.rows[0].total, 10);

  const limitIdx = idx++;
  const offsetIdx = idx++;
  const { rows } = await pool.query(
    `SELECT ${COLS} FROM payments ${where} ORDER BY created_at DESC LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
    [...values, limit, offset]
  );

  return { rows, total };
}

export async function create(pool, { orderId, userId, amountCents, currency, paymentMethod, transactionReference }) {
  const { rows } = await pool.query(
    `INSERT INTO payments (order_id, user_id, amount_cents, currency, payment_method, status, transaction_reference)
     VALUES ($1, $2, $3, $4, $5, 'pending', $6)
     RETURNING ${COLS}`,
    [orderId, userId, amountCents, currency, paymentMethod, transactionReference]
  );
  return rows[0];
}

export async function updateStatus(pool, id, status, failureReason) {
  const { rows } = await pool.query(
    `UPDATE payments SET status = $1, failure_reason = $2 WHERE id = $3 RETURNING ${COLS}`,
    [status, failureReason ?? null, id]
  );
  return rows[0];
}
