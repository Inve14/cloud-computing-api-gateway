# Catalog API Contract

## Overview

The Catalog service manages the product catalog, category taxonomy, and stock levels. It is **read-heavy**: the vast majority of traffic is product browsing, with occasional admin writes. To exploit this, all public read queries are routed to a PostgreSQL **read-replica**; writes go to the master.

The service exposes:
- **Public endpoints** (via Kong): product and category browsing, available to unauthenticated clients.
- **Admin endpoints** (via Kong, JWT with `role = "admin"`): product and stock management.
- **Internal endpoints** (Docker network only): product lookup and stock operations called by the Orders service during cart validation and checkout.

## Base URL

`/api/v1/catalog`

## Authentication

Public read endpoints require **no authentication**. Admin write endpoints require a `Bearer` token:

```
Authorization: Bearer <access_token>
```

The token is an RS256-signed JWT issued by the Users service. The Catalog service validates it against the Users service public key (distributed via Kong configuration).

JWT payload shape:
```json
{
  "sub": "<user-uuid>",
  "email": "user@example.com",
  "role": "admin",
  "iat": 1700000000,
  "exp": 1700000900
}
```

---

## Endpoints

### GET /api/v1/catalog/products

**Description**: List active products, paginated. Supports filtering by category and a full-text search on name and description. Served from the **read-replica**.
**Auth**: none
**Rate limit**: 100 req/min per IP

**Query parameters**:
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `page` | integer | `1` | Page number (1-based) |
| `limit` | integer | `20` | Items per page (max 100) |
| `category` | string | — | Filter by category `slug` |
| `q` | string | — | Full-text search on `name` and `description` |
| `sort` | string | `created_at_desc` | One of: `created_at_desc`, `price_asc`, `price_desc` |

**Response `200`**:
```json
{
  "data": [
    {
      "id": "770e8400-e29b-41d4-a716-446655440000",
      "category_id": "dd0e8400-e29b-41d4-a716-446655440000",
      "name": "Wireless Headphones",
      "slug": "wireless-headphones",
      "description": "High-quality over-ear headphones with ANC.",
      "price_cents": 2999,
      "currency": "EUR",
      "image_url": "https://cdn.example.com/headphones.jpg",
      "stock": {
        "quantity_available": 42
      }
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 1,
    "totalPages": 1
  }
}
```

Note: `quantity_reserved` is not exposed in the public response — only `quantity_available`.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Invalid query parameters |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/catalog/products/:productId

**Description**: Get a single product by ID, including full description and stock availability. Served from the **read-replica**.
**Auth**: none
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `productId` | UUID | The product ID |

**Response `200`**:
```json
{
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440000",
    "category_id": "dd0e8400-e29b-41d4-a716-446655440000",
    "name": "Wireless Headphones",
    "slug": "wireless-headphones",
    "description": "High-quality over-ear headphones with ANC.",
    "price_cents": 2999,
    "currency": "EUR",
    "image_url": "https://cdn.example.com/headphones.jpg",
    "is_active": true,
    "stock": {
      "quantity_available": 42
    },
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 404 | `NOT_FOUND` | Product not found or inactive |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/catalog/categories

**Description**: List all categories. Served from the **read-replica**.
**Auth**: none
**Rate limit**: 100 req/min per IP

**Response `200`**:
```json
{
  "data": [
    {
      "id": "dd0e8400-e29b-41d4-a716-446655440000",
      "name": "Electronics",
      "slug": "electronics",
      "description": "Electronic devices and accessories.",
      "created_at": "2025-01-01T00:00:00.000Z",
      "updated_at": "2025-01-01T00:00:00.000Z"
    }
  ]
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/catalog/categories/:categoryId

**Description**: Get a single category by ID. Served from the **read-replica**.
**Auth**: none
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `categoryId` | UUID | The category ID |

**Response `200`**:
```json
{
  "data": {
    "id": "dd0e8400-e29b-41d4-a716-446655440000",
    "name": "Electronics",
    "slug": "electronics",
    "description": "Electronic devices and accessories.",
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 404 | `NOT_FOUND` | Category not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/catalog/products

**Description**: Create a new product. Admin only. Writes to the **master**.
**Auth**: required, admin only
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "category_id": "dd0e8400-e29b-41d4-a716-446655440000",
  "name": "Wireless Headphones",
  "slug": "wireless-headphones",
  "description": "High-quality over-ear headphones with ANC.",
  "price_cents": 2999,
  "currency": "EUR",
  "image_url": "https://cdn.example.com/headphones.jpg",
  "initial_stock": 100
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `category_id` | UUID | yes | Must be an existing category |
| `name` | string | yes | Max 200 chars |
| `slug` | string | yes | Max 200 chars, URL-safe, must be unique |
| `description` | string | yes | |
| `price_cents` | integer | yes | Must be > 0 |
| `currency` | string | no | ISO 4217, default `"EUR"` |
| `image_url` | string | no | Max 500 chars |
| `initial_stock` | integer | no | Sets `quantity_available`; default 0 |

**Response `201`**:
```json
{
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440000",
    "category_id": "dd0e8400-e29b-41d4-a716-446655440000",
    "name": "Wireless Headphones",
    "slug": "wireless-headphones",
    "description": "High-quality over-ear headphones with ANC.",
    "price_cents": 2999,
    "currency": "EUR",
    "image_url": "https://cdn.example.com/headphones.jpg",
    "is_active": true,
    "stock": {
      "quantity_available": 100,
      "quantity_reserved": 0
    },
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Caller is not an admin |
| 404 | `CATEGORY_NOT_FOUND` | category_id does not exist |
| 409 | `SLUG_CONFLICT` | A product with this slug already exists |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### PATCH /api/v1/catalog/products/:productId

**Description**: Update a product's fields. All fields optional; at least one required. Admin only. Writes to the **master**.
**Auth**: required, admin only
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `productId` | UUID | The product ID |

**Request body** (all fields optional):
```json
{
  "name": "Wireless Headphones Pro",
  "price_cents": 3499,
  "is_active": false
}
```

**Response `200`**: full product object (same shape as `POST` response).

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Malformed fields or empty body |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Caller is not an admin |
| 404 | `NOT_FOUND` | Product not found |
| 409 | `SLUG_CONFLICT` | New slug already in use by another product |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### PATCH /api/v1/catalog/products/:productId/stock

**Description**: Adjust stock levels (restock or correction). Admin only. Writes to the **master**.
**Auth**: required, admin only
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `productId` | UUID | The product ID |

**Request body**:
```json
{
  "quantity_available": 150
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `quantity_available` | integer | yes | New absolute value; must be ≥ 0 |

**Response `200`**:
```json
{
  "data": {
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity_available": 150,
    "quantity_reserved": 3,
    "last_restocked_at": "2025-01-01T12:00:00.000Z",
    "updated_at": "2025-01-01T12:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or invalid quantity_available |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Caller is not an admin |
| 404 | `NOT_FOUND` | Product not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

## Internal Endpoints

These endpoints are **not exposed through Kong**. They are reachable only on the internal Docker network by trusted peer services (specifically the Orders service). No JWT is required.

### GET /internal/catalog/products/:id

**Description**: Fetch a product's details — including current price and active status — for use during cart validation and checkout. Called by the Orders service when an item is added to the cart (existence check) and at checkout time (snapshot of name and price). Returns inactive products with `is_active: false` so the caller can decide how to handle them.
**Auth**: none (internal network only)

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `id` | UUID | The product ID |

**Response `200`**:
```json
{
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440000",
    "name": "Wireless Headphones",
    "price_cents": 2999,
    "currency": "EUR",
    "is_active": true,
    "stock": {
      "quantity_available": 42,
      "quantity_reserved": 3
    }
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 404 | `NOT_FOUND` | Product not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /internal/catalog/stock/reserve

**Description**: Atomically decrease `quantity_available` and increase `quantity_reserved` for a product. Called by the Orders service at checkout when stock is allocated to a pending order. Fails with 409 if the requested quantity exceeds `quantity_available`.
**Auth**: none (internal network only)

**Request body**:
```json
{
  "product_id": "770e8400-e29b-41d4-a716-446655440000",
  "quantity": 2
}
```

| Field | Type | Notes |
|-------|------|-------|
| `product_id` | UUID | Must exist |
| `quantity` | integer | Must be > 0 |

**Response `200`**:
```json
{
  "data": {
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity_available": 40,
    "quantity_reserved": 5
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or invalid fields |
| 404 | `NOT_FOUND` | Product not found |
| 409 | `INSUFFICIENT_STOCK` | quantity > quantity_available |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /internal/catalog/stock/release

**Description**: Atomically decrease `quantity_reserved` and increase `quantity_available` for a product. Called by the Orders service when a pending order is cancelled or payment fails, to return the previously reserved stock to the available pool.
**Auth**: none (internal network only)

**Request body**:
```json
{
  "product_id": "770e8400-e29b-41d4-a716-446655440000",
  "quantity": 2
}
```

| Field | Type | Notes |
|-------|------|-------|
| `product_id` | UUID | Must exist |
| `quantity` | integer | Must be > 0; must not exceed `quantity_reserved` |

**Response `200`**:
```json
{
  "data": {
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity_available": 42,
    "quantity_reserved": 3
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or invalid fields |
| 404 | `NOT_FOUND` | Product not found |
| 409 | `RELEASE_EXCEEDS_RESERVED` | quantity > quantity_reserved |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

## Health Endpoints

### GET /health

**Auth**: none
**Description**: Liveness probe — always returns 200 if the process is up.

**Response `200`**:
```json
{
  "status": "ok",
  "service": "catalog",
  "timestamp": "2025-01-01T00:00:00.000Z"
}
```

### GET /ready

**Auth**: none
**Description**: Readiness probe — returns 200 only if the database connection (both master and read-replica) is healthy.

**Response `200`**:
```json
{
  "status": "ready",
  "service": "catalog",
  "checks": { "database_master": "ok", "database_replica": "ok" }
}
```

**Response `503`**:
```json
{
  "status": "not_ready",
  "service": "catalog",
  "checks": { "database_master": "ok", "database_replica": "error" }
}
```

---

## Rate Limiting

Applied by Kong at the gateway level.

| Endpoint | Limit |
|----------|-------|
| All endpoints | 100 req/min per IP |

Rate limit exceeded responses return HTTP 429 with error code `RATE_LIMITED`.

---

## Notes

- The catalog DB uses **PostgreSQL streaming replication** (1 master + 1 read-replica). All `GET` endpoints on the public and internal API are routed to the read-replica. All `POST`/`PATCH` and internal stock operations are routed to the master.
- `price_cents` stores prices as integers in the smallest currency unit (cents) to avoid floating-point precision issues. To display: `price = price_cents / 100`.
- The `slug` field is a URL-friendly unique identifier (e.g. `"wireless-headphones"`). It is separate from the UUID primary key and intended for use in human-readable URLs.
- `is_active = false` is a **soft delete** — the product is not destroyed, only hidden from public listings. Internal endpoints return inactive products so callers can detect stale cart items at checkout.
- `quantity_reserved` is **not exposed** in public endpoints to prevent leaking information about pending orders.
- The stock reserve/release operations (`POST /internal/catalog/stock/reserve` and `POST /internal/catalog/stock/release`) execute as single atomic `UPDATE` statements with a `CHECK >= 0` constraint to prevent negative stock. Concurrent requests are serialized at the database row level.
- All error responses follow RFC 7807 problem-details format: `{ "type": "...", "title": "...", "status": 400, "detail": "...", "correlationId": "..." }`.
