-- =============================================================================
-- Catalog Service — PostgreSQL schema initialisation
-- =============================================================================
-- Executed automatically by the postgres:16.3-alpine image on first container
-- startup (when /var/lib/postgresql/data is empty).
-- Re-running this script on an existing database is safe: all statements use
-- IF NOT EXISTS / CREATE OR REPLACE where applicable.
--
-- gen_random_uuid() is available as a built-in function since PostgreSQL 13;
-- no extension is required.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Shared trigger function: keeps updated_at in sync on every UPDATE.
-- Bound to each table individually below.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Table: categories
-- Product categories (e.g. "Electronics", "Books", "Clothing").
-- =============================================================================
CREATE TABLE IF NOT EXISTS categories (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  name        VARCHAR(100) NOT NULL UNIQUE,
  slug        VARCHAR(100) NOT NULL UNIQUE,
  description TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- UNIQUE constraints on name and slug already create implicit indexes;
-- no additional CREATE INDEX needed for the catalog schema.

CREATE OR REPLACE TRIGGER categories_set_updated_at
  BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: products
-- Products in the catalog. Soft-deleted via is_active = false.
-- =============================================================================
CREATE TABLE IF NOT EXISTS products (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID         NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  name        VARCHAR(200) NOT NULL,
  slug        VARCHAR(200) NOT NULL UNIQUE,
  description TEXT         NOT NULL,
  price_cents INTEGER      NOT NULL CHECK (price_cents > 0),
  currency    VARCHAR(3)   NOT NULL DEFAULT 'EUR',
  image_url   VARCHAR(500),
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Index for filtering by category (used by GET /api/v1/catalog/products?category=…).
CREATE INDEX IF NOT EXISTS products_category_id_idx
  ON products(category_id);

-- Composite index for listing active products by recency (the default sort).
CREATE INDEX IF NOT EXISTS products_is_active_created_at_idx
  ON products(is_active, created_at DESC);

CREATE OR REPLACE TRIGGER products_set_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: product_stock
-- Stock levels are kept in a separate table to allow high-frequency concurrent
-- updates (reserve / release) without locking the product row itself.
-- =============================================================================
CREATE TABLE IF NOT EXISTS product_stock (
  product_id          UUID        PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  quantity_available  INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_available >= 0),
  quantity_reserved   INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  last_restocked_at   TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE TRIGGER product_stock_set_updated_at
  BEFORE UPDATE ON product_stock
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Seed data — development only
-- Hardcoded UUIDs keep values stable across container restarts so that
-- Bruno collections and k6 scripts can reference them directly.
-- =============================================================================

-- Categories
INSERT INTO categories (id, name, slug, description)
VALUES
  (
    '11111111-1111-1111-1111-111111111111',
    'Electronics',
    'electronics',
    'Electronic devices and accessories'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'Books',
    'books',
    'Physical and digital books'
  )
ON CONFLICT (id) DO NOTHING;

-- Products
INSERT INTO products (id, category_id, name, slug, description, price_cents, currency, is_active)
VALUES
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'Wireless Headphones',
    'wireless-headphones',
    'High-quality over-ear headphones with active noise cancellation.',
    2999,
    'EUR',
    TRUE
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '11111111-1111-1111-1111-111111111111',
    'USB-C Cable',
    'usb-c-cable',
    'Braided 2m USB-C to USB-C cable, 100W fast charging supported.',
    999,
    'EUR',
    TRUE
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '22222222-2222-2222-2222-222222222222',
    'Clean Code',
    'clean-code',
    'A handbook of agile software craftsmanship by Robert C. Martin.',
    3499,
    'EUR',
    TRUE
  )
ON CONFLICT (id) DO NOTHING;

-- Stock levels for all seeded products
INSERT INTO product_stock (product_id, quantity_available, quantity_reserved)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 100, 0),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 250, 0),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',  50, 0)
ON CONFLICT (product_id) DO NOTHING;
