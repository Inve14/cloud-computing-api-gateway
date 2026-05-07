-- =============================================================================
-- Orders Service — PostgreSQL schema initialisation
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
-- Table: carts
-- One cart per user (UNIQUE on user_id). Created lazily on first cart-item add.
-- The cart record is never deleted — only its items are cleared on checkout or
-- DELETE /api/v1/cart.
-- =============================================================================
CREATE TABLE IF NOT EXISTS carts (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- UNIQUE constraint on user_id already creates an implicit index.

CREATE OR REPLACE TRIGGER carts_set_updated_at
  BEFORE UPDATE ON carts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: cart_items
-- Items in a user's active cart. No stock reservation at this stage.
-- Adding the same product twice increments quantity (UNIQUE on cart_id, product_id).
-- =============================================================================
CREATE TABLE IF NOT EXISTS cart_items (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id    UUID        NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  product_id UUID        NOT NULL,
  quantity   INTEGER     NOT NULL CHECK (quantity > 0),
  added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fetch all items of a cart.
CREATE INDEX IF NOT EXISTS cart_items_cart_id_idx
  ON cart_items(cart_id);

-- Enforce one row per product per cart; application uses ON CONFLICT to increment.
CREATE UNIQUE INDEX IF NOT EXISTS cart_items_cart_product_uidx
  ON cart_items(cart_id, product_id);

CREATE OR REPLACE TRIGGER cart_items_set_updated_at
  BEFORE UPDATE ON cart_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: orders
-- Immutable order header after creation; only `status` and `payment_id` change.
-- shipping_address is a JSONB snapshot taken at checkout time.
-- =============================================================================
CREATE TABLE IF NOT EXISTS orders (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID         NOT NULL,
  status           VARCHAR(20)  NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled')),
  total_cents      INTEGER      NOT NULL CHECK (total_cents > 0),
  currency         VARCHAR(3)   NOT NULL DEFAULT 'EUR',
  shipping_address JSONB        NOT NULL,
  payment_id       UUID,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Fetch order history for a specific user.
CREATE INDEX IF NOT EXISTS orders_user_id_idx   ON orders(user_id);
-- Admin filtering by status.
CREATE INDEX IF NOT EXISTS orders_status_idx    ON orders(status);
-- Default sort by recency.
CREATE INDEX IF NOT EXISTS orders_created_at_idx ON orders(created_at DESC);

CREATE OR REPLACE TRIGGER orders_set_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: order_items
-- Line items snapshotting product_name and price_cents at checkout time so that
-- subsequent catalog changes do not affect historical order records.
-- =============================================================================
CREATE TABLE IF NOT EXISTS order_items (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       UUID         NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id     UUID         NOT NULL,
  product_name   VARCHAR(200) NOT NULL,
  quantity       INTEGER      NOT NULL CHECK (quantity > 0),
  price_cents    INTEGER      NOT NULL CHECK (price_cents > 0),
  subtotal_cents INTEGER      NOT NULL CHECK (subtotal_cents > 0)
);

-- Fetch all line items of an order.
CREATE INDEX IF NOT EXISTS order_items_order_id_idx ON order_items(order_id);

-- =============================================================================
-- Seed data — development only
-- Hardcoded UUIDs keep values stable across container restarts.
--
-- user_id matches the customer seed in infrastructure/postgres/users/init.sql.
-- product_id values match the catalog seed in infrastructure/postgres/catalog/init.sql.
-- =============================================================================

INSERT INTO orders (id, user_id, status, total_cents, currency, shipping_address, payment_id)
VALUES (
  'dddddddd-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000002',   -- customer Mario Rossi (users seed)
  'paid',
  6997,
  'EUR',
  '{"street": "Via Roma 1", "city": "Milano", "zip_code": "20100", "country": "IT"}',
  'eeeeeeee-0000-0000-0000-000000000001'    -- placeholder payment_id (payments seed)
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO order_items (id, order_id, product_id, product_name, quantity, price_cents, subtotal_cents)
VALUES
  (
    'ffffffff-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',  -- Wireless Headphones (catalog seed)
    'Wireless Headphones',
    2,
    2999,
    5998
  ),
  (
    'ffffffff-0000-0000-0000-000000000002',
    'dddddddd-0000-0000-0000-000000000001',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',  -- USB-C Cable (catalog seed)
    'USB-C Cable',
    1,
    999,
    999
  )
ON CONFLICT (id) DO NOTHING;
