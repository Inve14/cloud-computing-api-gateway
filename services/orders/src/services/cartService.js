import { AppError } from '../errors.js';
import * as cartRepo from '../repositories/cartRepository.js';

function computeTotal(items) {
  return items.reduce((sum, i) => sum + i.quantity * i.unit_price_cents_snapshot, 0);
}

function formatItem(row) {
  return {
    id: row.id,
    product_id: row.product_id,
    product_name: row.product_name_snapshot,
    price_cents: row.unit_price_cents_snapshot,
    quantity: row.quantity,
    subtotal_cents: row.quantity * row.unit_price_cents_snapshot,
  };
}

function formatCartItem(row) {
  return {
    id: row.id,
    cart_id: row.cart_id,
    product_id: row.product_id,
    quantity: row.quantity,
    added_at: row.added_at,
    updated_at: row.updated_at,
  };
}

export async function getCart(pool, userId) {
  const cart = await cartRepo.findCartByUserId(pool, userId);

  if (!cart) {
    return { data: { id: null, user_id: userId, items: [], total_cents: 0 } };
  }

  const items = await cartRepo.listItemsByCartId(pool, cart.id);
  return {
    data: {
      id: cart.id,
      user_id: cart.user_id,
      items: items.map(formatItem),
      total_cents: computeTotal(items),
      created_at: cart.created_at,
      updated_at: cart.updated_at,
    },
  };
}

export async function addItem(pool, userId, { product_id, quantity, product_name_snapshot, unit_price_cents_snapshot }) {
  let cart = await cartRepo.findCartByUserId(pool, userId);
  if (!cart) cart = await cartRepo.createCart(pool, userId);

  const { item, inserted } = await cartRepo.upsertItem(
    pool,
    cart.id,
    product_id,
    quantity,
    product_name_snapshot,
    unit_price_cents_snapshot
  );

  return { data: formatCartItem(item), inserted };
}

export async function updateItem(pool, userId, itemId, quantity) {
  const existing = await cartRepo.getItemWithOwner(pool, itemId);
  if (!existing) throw new AppError(404, 'NOT_FOUND', 'Cart item not found');
  if (existing.user_id !== userId) throw new AppError(403, 'FORBIDDEN', 'Cart item belongs to a different user');

  const item = await cartRepo.updateItemQuantity(pool, itemId, quantity);
  return { data: formatCartItem(item) };
}

export async function removeItem(pool, userId, itemId) {
  const existing = await cartRepo.getItemWithOwner(pool, itemId);
  if (!existing) throw new AppError(404, 'NOT_FOUND', 'Cart item not found');
  if (existing.user_id !== userId) throw new AppError(403, 'FORBIDDEN', 'Cart item belongs to a different user');

  await cartRepo.deleteItem(pool, itemId);
}

export async function clearCart(pool, userId) {
  const cart = await cartRepo.findCartByUserId(pool, userId);
  if (cart) await cartRepo.clearItemsByCartId(pool, cart.id);
}
