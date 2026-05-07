-- =============================================================================
-- Payments Service — PostgreSQL schema initialisation
-- =============================================================================
-- Executed automatically by the postgres:16.3-alpine image on first container
-- startup (when /var/lib/postgresql/data is empty).
-- Re-running this script on an existing database is safe: all statements use
-- IF NOT EXISTS / CREATE OR REPLACE where applicable.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- Shared trigger function: keeps updated_at in sync on every UPDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Table: payments
-- One payment record per order. transaction_reference is a generated mock ID
-- (e.g. TXN-<date>-<random>) that is unique across all payments.
-- card_number_last4 is intentionally NOT stored — only the payment_method is
-- persisted (security: no card data at rest).
-- =============================================================================
CREATE TABLE IF NOT EXISTS payments (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID         NOT NULL,
  user_id               UUID         NOT NULL,
  amount_cents          INTEGER      NOT NULL CHECK (amount_cents > 0),
  currency              VARCHAR(3)   NOT NULL DEFAULT 'EUR',
  payment_method        VARCHAR(20)  NOT NULL
                                     CHECK (payment_method IN ('credit_card', 'paypal', 'bank_transfer')),
  status                VARCHAR(20)  NOT NULL DEFAULT 'pending'
                                     CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  transaction_reference VARCHAR(100) NOT NULL UNIQUE,
  failure_reason        VARCHAR(200),
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Lookup payment(s) for a given order (enforces the one-payment-per-order rule at query time).
CREATE INDEX IF NOT EXISTS payments_order_id_idx  ON payments(order_id);
-- Fetch payment history for a user.
CREATE INDEX IF NOT EXISTS payments_user_id_idx   ON payments(user_id);
-- Admin filtering by status.
CREATE INDEX IF NOT EXISTS payments_status_idx    ON payments(status);
-- UNIQUE constraint on transaction_reference already creates an implicit index.

CREATE OR REPLACE TRIGGER payments_set_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Seed data — development only
-- Hardcoded UUIDs keep values stable across container restarts.
--
-- id matches the payment_id placeholder used in infrastructure/postgres/orders/init.sql.
-- order_id matches the seed order in orders/init.sql.
-- user_id matches the customer seed in users/init.sql.
-- =============================================================================

INSERT INTO payments (
  id,
  order_id,
  user_id,
  amount_cents,
  currency,
  payment_method,
  status,
  transaction_reference,
  failure_reason
)
VALUES (
  'eeeeeeee-0000-0000-0000-000000000001',         -- matches orders seed payment_id
  'dddddddd-0000-0000-0000-000000000001',         -- order from orders seed
  'bbbbbbbb-0000-0000-0000-000000000002',         -- customer Mario Rossi (users seed)
  6997,
  'EUR',
  'credit_card',
  'completed',
  'TXN-2025-SEED0001',
  NULL
)
ON CONFLICT (id) DO NOTHING;
