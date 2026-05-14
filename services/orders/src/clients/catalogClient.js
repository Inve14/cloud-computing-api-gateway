const BASE_URL = process.env.CATALOG_SERVICE_URL ?? 'http://catalog:3001';
const TIMEOUT_MS = 3000;

async function fetchWithTimeout(url, options) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

export async function reserveStock(productId, quantity) {
  let res;
  try {
    res = await fetchWithTimeout(`${BASE_URL}/internal/catalog/stock/reserve`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ product_id: productId, quantity }),
    });
  } catch (err) {
    const e = new Error('Catalog service unreachable');
    e.code = 'DEPENDENCY_UNAVAILABLE';
    throw e;
  }

  if (res.status === 409) {
    const e = new Error(`Insufficient stock for product ${productId}`);
    e.code = 'INSUFFICIENT_STOCK';
    throw e;
  }

  if (!res.ok) {
    const e = new Error(`Catalog service error: ${res.status}`);
    e.code = 'DEPENDENCY_UNAVAILABLE';
    throw e;
  }
}

export async function releaseStock(productId, quantity) {
  try {
    const res = await fetchWithTimeout(`${BASE_URL}/internal/catalog/stock/release`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ product_id: productId, quantity }),
    });
    if (!res.ok) {
      throw new Error(`Catalog release failed: ${res.status}`);
    }
  } catch {
    // Release is best-effort in the saga compensation path — caller uses Promise.allSettled
  }
}
