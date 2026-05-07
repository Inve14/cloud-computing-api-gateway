-- =============================================================================
-- Users Service — PostgreSQL schema initialisation
-- =============================================================================
-- Executed automatically by the postgres:16.3-alpine image on first container
-- startup (when /var/lib/postgresql/data is empty).
-- Re-running this script on an existing database is safe: all statements use
-- IF NOT EXISTS / CREATE OR REPLACE where applicable.
-- =============================================================================

-- pgcrypto is required for gen_random_uuid() on PostgreSQL < 13.
-- On PostgreSQL 13+ it is a no-op (the function is built-in), but enabling
-- the extension is harmless and keeps the script version-agnostic.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

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
-- Table: users
-- User accounts. Passwords are stored as bcrypt hashes (cost factor 12).
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(254) NOT NULL UNIQUE,
  password_hash VARCHAR(60)  NOT NULL,
  first_name    VARCHAR(100) NOT NULL,
  last_name     VARCHAR(100) NOT NULL,
  phone         VARCHAR(20),
  role          VARCHAR(20)  NOT NULL DEFAULT 'customer'
                             CHECK (role IN ('customer', 'admin')),
  is_verified   BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Index on email is created implicitly by the UNIQUE constraint.
-- Explicit index on role for admin-panel queries filtering by role.
CREATE INDEX IF NOT EXISTS users_role_idx ON users(role);

CREATE OR REPLACE TRIGGER users_set_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Table: addresses
-- Shipping and billing addresses linked to a user.
-- =============================================================================
CREATE TABLE IF NOT EXISTS addresses (
  id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       VARCHAR(20)  NOT NULL CHECK (type IN ('shipping', 'billing')),
  street     VARCHAR(200) NOT NULL,
  city       VARCHAR(100) NOT NULL,
  zip_code   VARCHAR(20)  NOT NULL,
  country    VARCHAR(2)   NOT NULL DEFAULT 'IT',
  is_default BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Index for fetching all addresses of a user (most common query pattern).
CREATE INDEX IF NOT EXISTS addresses_user_id_idx ON addresses(user_id);

CREATE OR REPLACE TRIGGER addresses_set_updated_at
  BEFORE UPDATE ON addresses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Seed data — development only
-- Hardcoded UUIDs keep values stable across container restarts so that
-- Bruno collections and k6 scripts can reference them directly.
--
-- password_hash values are bcrypt cost-12 hashes of "Password123!"
-- precomputed offline — never generate hashes at schema initialisation time.
-- =============================================================================

INSERT INTO users (id, email, password_hash, first_name, last_name, role, is_verified)
VALUES
  (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'admin@example.com',
    '$2b$12$9rDAJlCcJ1.gTQynAqI/WeLBhGjDKx9lLD02/Ip7ocTwcrltCOcnG',
    'Admin',
    'User',
    'admin',
    TRUE
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'customer@example.com',
    '$2b$12$9rDAJlCcJ1.gTQynAqI/WeLBhGjDKx9lLD02/Ip7ocTwcrltCOcnG',
    'Mario',
    'Rossi',
    'customer',
    FALSE
  )
ON CONFLICT (id) DO NOTHING;

-- Seed address for the customer user
INSERT INTO addresses (id, user_id, type, street, city, zip_code, country, is_default)
VALUES
  (
    'cccccccc-0000-0000-0000-000000000003',
    'bbbbbbbb-0000-0000-0000-000000000002',
    'shipping',
    'Via Roma 1',
    'Milano',
    '20100',
    'IT',
    TRUE
  )
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- Table: refresh_tokens
-- Opaque refresh tokens (bcrypt-hashed). The token ID is the PK used for fast
-- lookup; only the hashed secret is stored — never the raw token value.
-- Rows are cleaned up on logout and on next login (expired purge).
-- =============================================================================
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         UUID         PRIMARY KEY,
  user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(60)  NOT NULL,
  expires_at TIMESTAMPTZ  NOT NULL,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx    ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS refresh_tokens_expires_at_idx ON refresh_tokens(expires_at);
