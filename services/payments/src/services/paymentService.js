import { randomUUID } from 'crypto';
import { AppError } from '../errors.js';
import * as paymentRepo from '../repositories/paymentRepository.js';

function generateTransactionReference() {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const rand = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  return `TXN-${date}-${rand}`;
}

function simulateDelay() {
  const min = parseInt(process.env.PAYMENT_DELAY_MS_MIN ?? '200', 10);
  const max = parseInt(process.env.PAYMENT_DELAY_MS_MAX ?? '500', 10);
  const ms = min + Math.random() * (max - min);
  return new Promise(resolve => setTimeout(resolve, ms));
}

export async function getPayment(pool, paymentId, userId, role) {
  const payment = await paymentRepo.findById(pool, paymentId);
  if (!payment) throw new AppError(404, 'NOT_FOUND', 'Payment not found');
  if (role !== 'admin' && payment.user_id !== userId) {
    throw new AppError(403, 'FORBIDDEN', 'Access denied');
  }
  return { data: payment };
}

export async function listPayments(pool, userId, role, { page = 1, limit = 20, status, order_id, user_id: filterUserId }) {
  if (filterUserId && role !== 'admin') {
    throw new AppError(403, 'FORBIDDEN', 'Admin role required to filter by user_id');
  }
  // non-admin always sees own; admin without filter sees all; admin with filter sees that user
  const targetUserId = role !== 'admin' ? userId : (filterUserId ?? null);

  const result = await paymentRepo.list(pool, {
    userId: targetUserId,
    page,
    limit,
    status,
    orderId: order_id,
  });

  return {
    data: result.rows,
    pagination: {
      page,
      limit,
      total: result.total,
      totalPages: Math.ceil(result.total / limit),
    },
  };
}

export async function processPayment(pool, { order_id, user_id, amount_cents, currency, payment_method, card_number_last4 }, logger) {
  const existing = await paymentRepo.findByOrderId(pool, order_id);
  if (existing) throw new AppError(409, 'CONFLICT', 'A payment for this order already exists');

  const transactionReference = generateTransactionReference();
  const payment = await paymentRepo.create(pool, {
    orderId: order_id,
    userId: user_id,
    amountCents: amount_cents,
    currency,
    paymentMethod: payment_method,
    transactionReference,
  });

  const failed = payment_method === 'credit_card' && card_number_last4 === '0000';

  await simulateDelay();

  const status = failed ? 'failed' : 'completed';
  const failureReason = failed ? 'Card declined' : null;

  const updated = await paymentRepo.updateStatus(pool, payment.id, status, failureReason);

  logger?.info({ paymentId: updated.id, orderId: order_id, status }, 'audit: payment processed');

  return {
    data: {
      payment_id: updated.id,
      status: updated.status,
      transaction_reference: updated.transaction_reference,
      failure_reason: updated.failure_reason,
    },
  };
}

export async function refundPayment(pool, paymentId, logger) {
  const payment = await paymentRepo.findById(pool, paymentId);
  if (!payment) throw new AppError(404, 'NOT_FOUND', 'Payment not found');
  if (payment.status !== 'completed') {
    throw new AppError(409, 'PAYMENT_NOT_COMPLETED', 'Only completed payments can be refunded');
  }

  const updated = await paymentRepo.updateStatus(pool, paymentId, 'refunded', null);

  logger?.info({ paymentId, orderId: payment.order_id }, 'audit: payment refunded');

  return { data: updated };
}
