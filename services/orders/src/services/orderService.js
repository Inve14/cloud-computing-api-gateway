import { AppError } from '../errors.js';
import * as orderRepo from '../repositories/orderRepository.js';
import * as cartRepo from '../repositories/cartRepository.js';
import * as catalogClient from '../clients/catalogClient.js';
import * as paymentsClient from '../clients/paymentsClient.js';

function formatItem(item) {
  return {
    id: item.id,
    product_id: item.product_id,
    product_name: item.product_name,
    quantity: item.quantity,
    price_cents: item.price_cents,
    subtotal_cents: item.subtotal_cents,
  };
}

function formatOrder(order, items) {
  return {
    id: order.id,
    user_id: order.user_id,
    status: order.status,
    total_cents: order.total_cents,
    currency: order.currency,
    shipping_address: order.shipping_address,
    payment_id: order.payment_id ?? null,
    items: items.map(formatItem),
    created_at: order.created_at,
    updated_at: order.updated_at,
  };
}

async function releaseAll(items) {
  await Promise.allSettled(
    items.map(item => catalogClient.releaseStock(item.product_id, item.quantity))
  );
}

export async function checkout(pool, userId, { shipping_address, payment }) {
  const cart = await cartRepo.findCartByUserId(pool, userId);
  const cartItems = cart ? await cartRepo.listItemsByCartId(pool, cart.id) : [];

  if (cartItems.length === 0) {
    throw new AppError(400, 'CART_EMPTY', 'Cart has no items to check out');
  }

  // Reserve stock — compensate on first failure
  const reservedItems = [];
  for (const item of cartItems) {
    try {
      await catalogClient.reserveStock(item.product_id, item.quantity);
      reservedItems.push(item);
    } catch (err) {
      await releaseAll(reservedItems);
      if (err.code === 'INSUFFICIENT_STOCK') {
        throw new AppError(409, 'INSUFFICIENT_STOCK', `Insufficient stock for product ${item.product_id}`);
      }
      throw new AppError(503, 'DEPENDENCY_UNAVAILABLE', 'Catalog service unreachable');
    }
  }

  const totalCents = cartItems.reduce(
    (sum, i) => sum + i.quantity * i.unit_price_cents_snapshot,
    0
  );

  // Create order record in a single SQL transaction (status = pending)
  const { order: pendingOrder, items: orderItems } = await orderRepo.createOrderWithItems(pool, {
    userId,
    totalCents,
    currency: 'EUR',
    shippingAddress: shipping_address,
    items: cartItems.map(i => ({
      product_id:    i.product_id,
      product_name:  i.product_name_snapshot,
      quantity:      i.quantity,
      price_cents:   i.unit_price_cents_snapshot,
      subtotal_cents: i.quantity * i.unit_price_cents_snapshot,
    })),
  });

  // Process payment — compensate on error
  let paymentResult;
  try {
    paymentResult = await paymentsClient.processPayment({
      order_id:          pendingOrder.id,
      user_id:           userId,
      amount_cents:      totalCents,
      currency:          'EUR',
      payment_method:    payment.method,
      card_number_last4: payment.card_number_last4 ?? null,
    });
  } catch {
    await releaseAll(cartItems);
    await orderRepo.updateOrderStatus(pool, pendingOrder.id, 'cancelled');
    throw new AppError(503, 'DEPENDENCY_UNAVAILABLE', 'Payments service unreachable');
  }

  if (paymentResult.status === 'failed') {
    await releaseAll(cartItems);
    await orderRepo.updateOrderStatus(pool, pendingOrder.id, 'cancelled');
    throw new AppError(402, 'PAYMENT_FAILED', 'Payment was declined');
  }

  // Success — finalise
  const paidOrder = await orderRepo.updateOrderStatus(
    pool,
    pendingOrder.id,
    'paid',
    paymentResult.payment_id
  );

  await cartRepo.clearItemsByCartId(pool, cart.id);

  return { data: formatOrder(paidOrder, orderItems) };
}

export async function getOrder(pool, orderId, userId, role) {
  const result = await orderRepo.findOrderWithItems(pool, orderId);
  if (!result) throw new AppError(404, 'NOT_FOUND', 'Order not found');

  if (role !== 'admin' && result.order.user_id !== userId) {
    throw new AppError(403, 'FORBIDDEN', 'Order belongs to a different user');
  }

  return { data: formatOrder(result.order, result.items) };
}

export async function listOrders(pool, userId, role, { page = 1, limit = 20, status, user_id: filterUserId }) {
  if (filterUserId && role !== 'admin') {
    throw new AppError(403, 'FORBIDDEN', 'Admin role required to filter by user_id');
  }

  const targetUserId = role !== 'admin' ? userId : (filterUserId ?? null);

  const { rows, total } = await orderRepo.list(pool, {
    userId: targetUserId,
    page,
    limit,
    status,
  });

  return {
    data: rows.map(o => ({
      id:          o.id,
      user_id:     o.user_id,
      status:      o.status,
      total_cents: o.total_cents,
      currency:    o.currency,
      payment_id:  o.payment_id ?? null,
      created_at:  o.created_at,
      updated_at:  o.updated_at,
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
}
