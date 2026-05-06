# Database Schema

This document describes the database schema for each microservice. We follow the **database-per-service** pattern: each service owns its data and exposes it only via its API. Cross-service references (e.g. `user_id` in `orders`) are **logical foreign keys** — they are not enforced at the database level because they point to a different database.

All tables use `UUID` primary keys (generated with `gen_random_uuid()`) and include `created_at` / `updated_at` timestamps managed automatically.

---

## Catalog Service

### Table: `categories`

Product categories (e.g. "Electronics", "Books", "Clothing").

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK, default gen_random_uuid() | |
| `name` | VARCHAR(100) | NOT NULL, UNIQUE | Display name |
| `slug` | VARCHAR(100) | NOT NULL, UNIQUE | URL-friendly identifier |
| `description` | TEXT | NULLABLE | Long description |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: unique on `slug`, unique on `name`.

### Table: `products`

Products in the catalog.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `category_id` | UUID | FK → categories.id, ON DELETE RESTRICT | |
| `name` | VARCHAR(200) | NOT NULL | |
| `slug` | VARCHAR(200) | NOT NULL, UNIQUE | URL-friendly identifier |
| `description` | TEXT | NOT NULL | |
| `price_cents` | INTEGER | NOT NULL, CHECK > 0 | Price in cents (e.g. 2999 = €29.99) |
| `currency` | VARCHAR(3) | NOT NULL, default 'EUR' | ISO 4217 |
| `image_url` | VARCHAR(500) | NULLABLE | |
| `is_active` | BOOLEAN | NOT NULL, default TRUE | Soft-delete flag |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: unique on `slug`, on `category_id` (for filtering by category), on `(is_active, created_at)` (for listing active products by recency).

**Note on `price_cents`**: storing prices as integers in the smallest currency unit avoids floating-point precision issues. To display: `price = price_cents / 100`.

### Table: `product_stock`

Stock tracking, separated from `products` to allow concurrent stock updates without locking the product row.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `product_id` | UUID | PK + FK → products.id, ON DELETE CASCADE | |
| `quantity_available` | INTEGER | NOT NULL, default 0, CHECK >= 0 | Items available for purchase |
| `quantity_reserved` | INTEGER | NOT NULL, default 0, CHECK >= 0 | Items in someone's cart |
| `last_restocked_at` | TIMESTAMPTZ | NULLABLE | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Concurrency note**: when adding to cart, `quantity_available` decreases and `quantity_reserved` increases, atomically. When the order is paid, `quantity_reserved` decreases. When the cart times out, `quantity_reserved` decreases and `quantity_available` increases.

---

## Users Service

### Table: `users`

User accounts.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `email` | VARCHAR(254) | NOT NULL, UNIQUE | RFC 5321 max length |
| `password_hash` | VARCHAR(60) | NOT NULL | bcrypt hash, cost factor 12 |
| `first_name` | VARCHAR(100) | NOT NULL | |
| `last_name` | VARCHAR(100) | NOT NULL | |
| `phone` | VARCHAR(20) | NULLABLE | E.164 format |
| `role` | VARCHAR(20) | NOT NULL, default 'customer', CHECK IN ('customer', 'admin') | |
| `is_verified` | BOOLEAN | NOT NULL, default FALSE | Email verification flag |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: unique on `email` (also used for login lookups).

**Security note**: `password_hash` is bcrypt with cost factor 12. The plaintext password is **never** stored or logged.

### Table: `addresses`

User addresses for shipping and billing.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | NOT NULL, FK → users.id, ON DELETE CASCADE | |
| `type` | VARCHAR(20) | NOT NULL, CHECK IN ('shipping', 'billing') | |
| `street` | VARCHAR(200) | NOT NULL | |
| `city` | VARCHAR(100) | NOT NULL | |
| `zip_code` | VARCHAR(20) | NOT NULL | |
| `country` | VARCHAR(2) | NOT NULL, default 'IT' | ISO 3166-1 alpha-2 |
| `is_default` | BOOLEAN | NOT NULL, default FALSE | |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: on `user_id` (for fetching all addresses of a user).

**Business rule**: only one address per `(user_id, type)` can have `is_default = TRUE` — enforced in application logic.

---

## Orders Service

The Orders service owns the entire purchasing flow: shopping cart, checkout, and order lifecycle. The cart and order entities live in the same database since they share the same bounded context (the customer's purchasing journey).

### Table: `carts`

A cart represents a user's current shopping session. Each user can have **at most one active cart** at a time.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | NOT NULL, UNIQUE | Logical FK to users.id; UNIQUE enforces one cart per user |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | Updated whenever an item is added/removed |

**Indexes**: unique on `user_id`.

**Lifecycle**:
- A cart is created lazily on the first `POST /api/v1/cart/items` call by a user.
- On successful checkout (`POST /api/v1/cart/checkout`), the cart is **emptied** but the cart record itself remains (for the next shopping session).
- On `DELETE /api/v1/cart`, all `cart_items` are deleted but the cart record remains.

### Table: `cart_items`

Items currently in a user's cart. **No stock reservation happens at this stage** — stock is only reserved at checkout, to avoid users hoarding items by leaving them in carts indefinitely.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `cart_id` | UUID | NOT NULL, FK → carts.id, ON DELETE CASCADE | |
| `product_id` | UUID | NOT NULL | Logical FK to products.id (different DB) |
| `quantity` | INTEGER | NOT NULL, CHECK > 0 | |
| `added_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: on `cart_id` (for fetching all items of a cart), unique on `(cart_id, product_id)` (a product appears at most once per cart — adding the same product twice increments `quantity` instead of creating a duplicate row).

**Important note on stock**: when an item is added to the cart, **no stock reservation is made on the catalog service**. Stock is checked (to inform the user about availability) but only **reserved** during checkout. This means two users can have the same item in their carts simultaneously; whoever checks out first wins. This trade-off is intentional: reserving stock at cart-add time leads to "phantom out-of-stock" issues where users hoard inventory by leaving items in carts.

---

### Table: `orders`

Order header.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | NOT NULL | Logical FK to users.id (different DB) |
| `status` | VARCHAR(20) | NOT NULL, default 'pending', CHECK IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled') | |
| `total_cents` | INTEGER | NOT NULL, CHECK > 0 | Total order amount in cents |
| `currency` | VARCHAR(3) | NOT NULL, default 'EUR' | |
| `shipping_address` | JSONB | NOT NULL | Snapshot of address at order time |
| `payment_id` | UUID | NULLABLE | Logical FK to payments.id |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: on `user_id` (for fetching user's order history), on `status` (for admin filtering), on `created_at` (for recency).

**Note on `shipping_address` (JSONB)**: we snapshot the address at the time of the order. If the user later changes their address, the order keeps the original shipping destination.

### Table: `order_items`

Order line items.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `order_id` | UUID | NOT NULL, FK → orders.id, ON DELETE CASCADE | |
| `product_id` | UUID | NOT NULL | Logical FK to products.id (different DB) |
| `product_name` | VARCHAR(200) | NOT NULL | Snapshot at order time |
| `quantity` | INTEGER | NOT NULL, CHECK > 0 | |
| `price_cents` | INTEGER | NOT NULL, CHECK > 0 | Unit price at order time |
| `subtotal_cents` | INTEGER | NOT NULL, CHECK > 0 | quantity × price_cents |

**Indexes**: on `order_id` (for fetching all items of an order).

**Note on snapshotting**: `product_name` and `price_cents` are stored at order time. If the product is later renamed or repriced, the order remains historically accurate.

---

## Payments Service

### Table: `payments`

Payment transactions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `order_id` | UUID | NOT NULL | Logical FK to orders.id |
| `user_id` | UUID | NOT NULL | Logical FK to users.id |
| `amount_cents` | INTEGER | NOT NULL, CHECK > 0 | |
| `currency` | VARCHAR(3) | NOT NULL, default 'EUR' | |
| `payment_method` | VARCHAR(20) | NOT NULL, CHECK IN ('credit_card', 'paypal', 'bank_transfer') | |
| `status` | VARCHAR(20) | NOT NULL, default 'pending', CHECK IN ('pending', 'completed', 'failed', 'refunded') | |
| `transaction_reference` | VARCHAR(100) | NOT NULL, UNIQUE | Mock transaction ID |
| `failure_reason` | VARCHAR(200) | NULLABLE | Populated only when status='failed' |
| `created_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, default NOW() | |

**Indexes**: on `order_id`, on `user_id`, on `status`, unique on `transaction_reference`.

**Simulation note**: this service does NOT integrate with real payment providers. The behavior is deterministic and configurable via the `payment_method` and other rules:
- `credit_card` ending in 0000 → always fails (for demo of fault tolerance)
- All others → succeed after a simulated 200-500ms delay

---

## Cross-Service Relationships

The following diagram shows the logical relationships between data across services. These are NOT enforced at the database level (different databases) but are maintained by application logic.

```
users.id  ──────────────────────────┐
                                    │
                                    ▼
catalog.products.id  ──────►  orders.order_items.product_id
                                    │
                                    ▼
                             orders.orders.id  ──────►  payments.payments.order_id
                                                              │
                                                              ▼
                                                     payments.payments.user_id  ◄──── users.id
```

### Consistency strategy

Since cross-service FKs are not enforced, we maintain consistency through:

1. **Validation at API level**: when creating an order, the `orders` service calls the `catalog` service to verify product existence and stock availability.
2. **Compensating transactions**: if a payment fails after stock has been reserved, the `orders` service publishes a "cancel reservation" event back to `catalog`.
3. **Snapshotting**: critical data (product name, price, shipping address) is snapshotted at the time of the operation, so later changes in the source service don't affect historical records.

---

## Database Replication

The `catalog` database uses **PostgreSQL streaming replication** with one read-replica:

- **Master** (read-write): handles all `INSERT`, `UPDATE`, `DELETE`, plus admin queries.
- **Read-replica** (read-only): handles product listings, search, and detail queries from the public API.

This pattern is appropriate because catalog is **read-heavy**: most traffic is product browsing, with occasional admin updates. The replica reduces load on the master and improves read latency.

The other databases (`users`, `orders`, `payments`) use a single node — replication would add complexity without significant benefit for this scale.