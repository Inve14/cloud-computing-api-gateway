const BASE_URL = process.env.PAYMENTS_SERVICE_URL ?? 'http://payments:3004';
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

export async function processPayment({ order_id, user_id, amount_cents, currency, payment_method, card_number_last4 }) {
  let res;
  try {
    res = await fetchWithTimeout(`${BASE_URL}/internal/payments/process`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order_id, user_id, amount_cents, currency, payment_method, card_number_last4 }),
    });
  } catch {
    const e = new Error('Payments service unreachable');
    e.code = 'DEPENDENCY_UNAVAILABLE';
    throw e;
  }

  if (!res.ok) {
    const e = new Error(`Payments service error: ${res.status}`);
    e.code = 'DEPENDENCY_UNAVAILABLE';
    throw e;
  }

  const json = await res.json();
  return json.data; // { payment_id, status, transaction_reference, failure_reason }
}
