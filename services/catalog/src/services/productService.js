import { AppError } from '../errors.js';
import * as productRepo from '../repositories/productRepository.js';
import * as categoryRepo from '../repositories/categoryRepository.js';

// ---------- Public ----------

export async function listProducts(pool, params) {
  const { rows, total } = await productRepo.listProducts(pool, params);

  return {
    data: rows.map((r) => ({
      id: r.id,
      category_id: r.category_id,
      name: r.name,
      slug: r.slug,
      description: r.description,
      price_cents: r.price_cents,
      currency: r.currency,
      image_url: r.image_url ?? null,
      stock: { quantity_available: r.quantity_available },
    })),
    pagination: {
      page: params.page,
      limit: params.limit,
      total,
      totalPages: total === 0 ? 1 : Math.ceil(total / params.limit),
    },
  };
}

export async function getProduct(pool, id) {
  const p = await productRepo.getProductById(pool, id);
  if (!p) throw new AppError(404, 'NOT_FOUND', 'Product not found or inactive');

  return {
    data: {
      id: p.id,
      category_id: p.category_id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price_cents: p.price_cents,
      currency: p.currency,
      image_url: p.image_url ?? null,
      is_active: p.is_active,
      stock: { quantity_available: p.quantity_available },
      created_at: p.created_at,
      updated_at: p.updated_at,
    },
  };
}

// ---------- Admin ----------

export async function createProduct(pool, body) {
  const category = await categoryRepo.getCategoryById(pool, body.category_id);
  if (!category) throw new AppError(404, 'CATEGORY_NOT_FOUND', 'Category not found');

  let result;
  try {
    result = await productRepo.createProduct(pool, body);
  } catch (err) {
    if (err.code === '23505') throw new AppError(409, 'SLUG_CONFLICT', 'A product with this slug already exists');
    throw err;
  }

  const { product: p, stock: s } = result;
  return {
    data: {
      id: p.id,
      category_id: p.category_id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price_cents: p.price_cents,
      currency: p.currency,
      image_url: p.image_url ?? null,
      is_active: p.is_active,
      stock: { quantity_available: s.quantity_available, quantity_reserved: s.quantity_reserved },
      created_at: p.created_at,
      updated_at: p.updated_at,
    },
  };
}

export async function updateProduct(pool, id, body) {
  const existing = await productRepo.getProductWithStock(pool, id);
  if (!existing) throw new AppError(404, 'NOT_FOUND', 'Product not found');

  try {
    await productRepo.updateProduct(pool, id, body);
  } catch (err) {
    if (err.code === '23505') throw new AppError(409, 'SLUG_CONFLICT', 'Slug already in use by another product');
    if (err.code === '23503') throw new AppError(404, 'CATEGORY_NOT_FOUND', 'Category not found');
    throw err;
  }

  const p = await productRepo.getProductWithStock(pool, id);
  return {
    data: {
      id: p.id,
      category_id: p.category_id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price_cents: p.price_cents,
      currency: p.currency,
      image_url: p.image_url ?? null,
      is_active: p.is_active,
      stock: { quantity_available: p.quantity_available, quantity_reserved: p.quantity_reserved },
      created_at: p.created_at,
      updated_at: p.updated_at,
    },
  };
}

export async function setStock(pool, productId, quantityAvailable) {
  const stock = await productRepo.setStock(pool, productId, quantityAvailable);
  if (!stock) throw new AppError(404, 'NOT_FOUND', 'Product not found');
  return { data: stock };
}

// ---------- Internal ----------

export async function getProductInternal(pool, id) {
  const p = await productRepo.getProductByIdInternal(pool, id);
  if (!p) throw new AppError(404, 'NOT_FOUND', 'Product not found');

  return {
    data: {
      id: p.id,
      name: p.name,
      price_cents: p.price_cents,
      currency: p.currency,
      is_active: p.is_active,
      stock: { quantity_available: p.quantity_available, quantity_reserved: p.quantity_reserved },
    },
  };
}

export async function reserveStock(pool, productId, quantity) {
  const exists = await productRepo.productExists(pool, productId);
  if (!exists) throw new AppError(404, 'NOT_FOUND', 'Product not found');

  const stock = await productRepo.reserveStock(pool, productId, quantity);
  if (!stock) throw new AppError(409, 'INSUFFICIENT_STOCK', 'Insufficient stock to reserve the requested quantity');

  return { data: { product_id: stock.product_id, quantity_available: stock.quantity_available, quantity_reserved: stock.quantity_reserved } };
}

export async function releaseStock(pool, productId, quantity) {
  const exists = await productRepo.productExists(pool, productId);
  if (!exists) throw new AppError(404, 'NOT_FOUND', 'Product not found');

  const stock = await productRepo.releaseStock(pool, productId, quantity);
  if (!stock) throw new AppError(409, 'RELEASE_EXCEEDS_RESERVED', 'Cannot release more stock than is currently reserved');

  return { data: { product_id: stock.product_id, quantity_available: stock.quantity_available, quantity_reserved: stock.quantity_reserved } };
}
