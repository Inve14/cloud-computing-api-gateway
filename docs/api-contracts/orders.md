# Orders API Contract

## Overview

The Orders service owns the entire purchasing journey: shopping cart management, checkout, and order lifecycle. It acts as the **orchestrator** of the checkout flow — it calls the catalog service to verify product details and reserve stock, then calls the payments service to process payment, and applies compensating transactions on failure.

The cart and order entities live in the **same database** (the Orders service DB) because they share the same bounded context: both represent stages of a customer's purchasing journey. The cart is a pre-order state; the order is the committed record after checkout.

Orders are immutable records once placed: only the `status` field changes over time. Product names, prices, and shipping addresses are snapshotted at order creation to preserve historical accuracy.

## Base URLs

This service handles two path groups, both served by the same Fastify instance:

| Path group | Purpose |
|------------|---------|
| `/api/v1/cart` | Shopping cart management |
| `/api/v1/orders` | Order history and management |

## Authentication

All public endpoints require a `Bearer` token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

The token is an RS256-signed JWT issued by the Users service. The Orders service validates it against the Users service public key (distributed via Kong configuration).

JWT payload shape:
```json
{
  "sub": "<user-uuid>",
  "email": "user@example.com",
  "role": "customer",
  "iat": 1700000000,
  "exp": 1700000900
}
```

---

## Checkout Flow

The following sequence describes what happens when a client calls `POST /api/v1/cart/checkout`:

```
Client
  │
  ▼
POST /api/v1/cart/checkout  (Kong → orders-service)
  │
  ├─ 1. Validate JWT, extract user_id and role
  ├─ 2. Validate request body (shipping_address_id, payment)
  ├─ 3. Load user's cart — 400 CART_EMPTY if no items
  ├─ 4. GET /internal/catalog/products/:id  (for each cart item)
  │       → verify product exists and is active; snapshot name and price
  ├─ 5. POST /internal/catalog/stock/reserve  (for each item)
  │       → atomically decrease quantity_available, increase quantity_reserved
  │       → 409 INSUFFICIENT_STOCK if any item cannot be reserved
  ├─ 6. Create order record in DB  (status = "pending")
  ├─ 7. POST /internal/payments/process
  │       → initiate payment; payments service responds synchronously
  │
  ├─ 8a. Payment COMPLETED
  │       → update order status = "paid"
  │       → clear cart items (cart record preserved for next session)
  │       → return 201 to client
  │
  └─ 8b. Payment FAILED
          → POST /internal/catalog/stock/release  (for each item)
          → update order status = "cancelled"
          → cart items preserved (user can retry with a different payment)
          → return 402 to client
```

HTTP client timeouts to downstream services: **3 seconds**, with exponential backoff (max 3 retries) for transient errors. Circuit breaker at Kong gateway level prevents cascading failures.

---

## Cart Endpoints

The cart endpoints manage the user's current shopping session. The cart is a pre-order state: items can be added, modified, or removed without any stock impact. Stock is only reserved at checkout time.

### GET /api/v1/cart

**Description**: Return the authenticated user's cart, including all items. If the user has no cart yet, returns an empty cart response **without creating a cart record**. Product names, prices, and stock availability are **fetched live from the catalog service at read time** (not snapshotted). `total_cents` is computed server-side.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Response `200`** (cart with items):
```json
{
  "data": {
    "id": "bb0e8400-e29b-41d4-a716-446655440000",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "items": [
      {
        "id": "cc0e8400-e29b-41d4-a716-446655440000",
        "product_id": "770e8400-e29b-41d4-a716-446655440000",
        "product_name": "Wireless Headphones",
        "price_cents": 2999,
        "quantity": 2,
        "subtotal_cents": 5998,
        "stock_available": true
      }
    ],
    "total_cents": 5998,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Response `200`** (no cart record exists yet):
```json
{
  "data": {
    "id": null,
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "items": [],
    "total_cents": 0
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 503 | `DEPENDENCY_UNAVAILABLE` | Catalog service unreachable when fetching product details |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/cart/items

**Description**: Add a product to the cart. Creates the cart record lazily if the user has no cart yet. If the product is already in the cart, **increments quantity** rather than creating a duplicate row (enforced by a `UNIQUE` constraint on `(cart_id, product_id)`). Validates product existence and active status against catalog, but does **not** reserve stock.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "product_id": "770e8400-e29b-41d4-a716-446655440000",
  "quantity": 2
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `product_id` | UUID | yes | Must be an active product in catalog |
| `quantity` | integer | yes | Must be > 0 |

**Response `201`** (item newly added):
```json
{
  "data": {
    "id": "cc0e8400-e29b-41d4-a716-446655440000",
    "cart_id": "bb0e8400-e29b-41d4-a716-446655440000",
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity": 2,
    "added_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Response `200`** (product already in cart — quantity incremented):
```json
{
  "data": {
    "id": "cc0e8400-e29b-41d4-a716-446655440000",
    "cart_id": "bb0e8400-e29b-41d4-a716-446655440000",
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity": 4,
    "added_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T12:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist or is inactive |
| 429 | `RATE_LIMITED` | Too many requests |
| 503 | `DEPENDENCY_UNAVAILABLE` | Catalog service unreachable |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### PATCH /api/v1/cart/items/:itemId

**Description**: Update the quantity of a specific cart item. Quantity must be ≥ 1 — to remove an item entirely use `DELETE /api/v1/cart/items/:itemId` instead.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `itemId` | UUID | The cart item ID |

**Request body**:
```json
{
  "quantity": 3
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `quantity` | integer | yes | Must be ≥ 1 |

**Response `200`**:
```json
{
  "data": {
    "id": "cc0e8400-e29b-41d4-a716-446655440000",
    "cart_id": "bb0e8400-e29b-41d4-a716-446655440000",
    "product_id": "770e8400-e29b-41d4-a716-446655440000",
    "quantity": 3,
    "added_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T12:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing quantity, or quantity < 1 |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Cart item belongs to a different user |
| 404 | `NOT_FOUND` | Cart item not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### DELETE /api/v1/cart/items/:itemId

**Description**: Remove a single item from the cart.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `itemId` | UUID | The cart item ID |

**Response `204`**: no body.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Cart item belongs to a different user |
| 404 | `NOT_FOUND` | Cart item not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### DELETE /api/v1/cart

**Description**: Clear all items from the cart. The cart record itself is preserved for the next shopping session. If the user has no cart, returns 204 with no side effects (idempotent).
**Auth**: required
**Rate limit**: 100 req/min per IP

**Response `204`**: no body.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/cart/checkout

**Description**: Transform the current cart into a paid order. This is the primary entry point for order creation. See [Checkout Flow](#checkout-flow) for the full orchestration sequence. On payment success the cart is emptied and the order (status `paid`) is returned. On payment failure the cart is preserved so the user can retry with a different payment method.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "shipping_address_id": "660e8400-e29b-41d4-a716-446655440001",
  "payment": {
    "method": "credit_card",
    "card_number_last4": "1234"
  }
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `shipping_address_id` | UUID | yes | Must belong to the authenticated user |
| `payment.method` | string | yes | `"credit_card"`, `"paypal"`, or `"bank_transfer"` |
| `payment.card_number_last4` | string | no | Required when `method = "credit_card"` |

**Response `201`** (payment succeeded):
```json
{
  "data": {
    "id": "880e8400-e29b-41d4-a716-446655440000",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "paid",
    "total_cents": 8997,
    "currency": "EUR",
    "shipping_address": {
      "street": "Via Roma 1",
      "city": "Milano",
      "zip_code": "20100",
      "country": "IT"
    },
    "payment_id": "990e8400-e29b-41d4-a716-446655440000",
    "items": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440000",
        "product_id": "770e8400-e29b-41d4-a716-446655440000",
        "product_name": "Wireless Headphones",
        "quantity": 2,
        "price_cents": 2999,
        "subtotal_cents": 5998
      },
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440001",
        "product_id": "770e8400-e29b-41d4-a716-446655440001",
        "product_name": "USB-C Cable",
        "quantity": 1,
        "price_cents": 2999,
        "subtotal_cents": 2999
      }
    ],
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 400 | `CART_EMPTY` | Cart has no items to check out |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 402 | `PAYMENT_FAILED` | Payment was declined; order cancelled, stock released, cart preserved |
| 404 | `PRODUCT_NOT_FOUND` | One or more cart items reference an inactive or deleted product |
| 404 | `ADDRESS_NOT_FOUND` | shipping_address_id not found or not owned by this user |
| 409 | `INSUFFICIENT_STOCK` | One or more items have less stock than requested |
| 429 | `RATE_LIMITED` | Too many requests |
| 500 | `INTERNAL_ERROR` | Unexpected server error |
| 503 | `DEPENDENCY_UNAVAILABLE` | Catalog or payments service unreachable after retries |

---

## Endpoints

> **Order creation** now happens via `POST /api/v1/cart/checkout` — see [Cart Endpoints](#cart-endpoints).

### GET /api/v1/orders/:orderId

**Description**: Get a single order by ID, including all line items. Users can only see their own orders. Admins (`role = "admin"`) can see any order.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `orderId` | UUID | The order ID |

**Response `200`**:
```json
{
  "data": {
    "id": "880e8400-e29b-41d4-a716-446655440000",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "paid",
    "total_cents": 8997,
    "currency": "EUR",
    "shipping_address": {
      "street": "Via Roma 1",
      "city": "Milano",
      "zip_code": "20100",
      "country": "IT"
    },
    "payment_id": "990e8400-e29b-41d4-a716-446655440000",
    "items": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440000",
        "product_id": "770e8400-e29b-41d4-a716-446655440000",
        "product_name": "Wireless Headphones",
        "quantity": 2,
        "price_cents": 2999,
        "subtotal_cents": 5998
      }
    ],
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Order belongs to a different user (non-admin) |
| 404 | `NOT_FOUND` | Order not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/orders

**Description**: List orders for the authenticated user, paginated. Normal users see only their own orders. Admins can additionally filter by `user_id` and `status`.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Query parameters**:
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `page` | integer | `1` | Page number (1-based) |
| `limit` | integer | `20` | Items per page (max 100) |
| `status` | string | — | Filter by order status |
| `user_id` | UUID | — | Admin only: filter by user |

**Response `200`**:
```json
{
  "data": [
    {
      "id": "880e8400-e29b-41d4-a716-446655440000",
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "status": "paid",
      "total_cents": 8997,
      "currency": "EUR",
      "payment_id": "990e8400-e29b-41d4-a716-446655440000",
      "created_at": "2025-01-01T00:00:00.000Z",
      "updated_at": "2025-01-01T00:00:00.000Z"
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

Note: the list response does not include `items` (line items) to reduce payload size. Fetch a single order to get line items.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Invalid query parameters |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Non-admin tried to filter by `user_id` |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### DELETE /api/v1/orders/:orderId

**Description**: Cancel an order. Only orders with `status = "pending"` can be cancelled (a paid order requires a refund, which is handled by the payments service). On cancellation, the Orders service calls catalog to release reserved stock.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `orderId` | UUID | The order ID |

**Cancellation flow**:
1. Verify order belongs to requesting user (or admin).
2. Verify `status = "pending"` — 409 otherwise.
3. For each order item: call `POST /internal/catalog/stock/release`.
4. Update order `status = "cancelled"`.
5. Return 204.

**Response `204`**: no body.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Order belongs to a different user (non-admin) |
| 404 | `NOT_FOUND` | Order not found |
| 409 | `CONFLICT` | Order cannot be cancelled (status is not `pending`) |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

## Internal Endpoints

These endpoints are **not exposed through Kong**. They are reachable only on the internal Docker network by trusted peer services. No JWT is required.

### POST /internal/orders/:orderId/payment-callback

**Description**: Called by the payments service to notify the Orders service of a payment outcome. The Orders service updates the order status accordingly. If the payment failed, stock reservation is released by calling catalog.
**Auth**: none (internal network only)

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `orderId` | UUID | The order ID associated with the payment |

**Request body**:
```json
{
  "payment_id": "990e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "failure_reason": null
}
```

| Field | Type | Notes |
|-------|------|-------|
| `payment_id` | UUID | The payments service record ID |
| `status` | string | `"completed"` or `"failed"` |
| `failure_reason` | string\|null | Populated only when `status = "failed"` |

**On `status = "completed"`**:
- Set `orders.status = "paid"` and `orders.payment_id = payment_id`.

**On `status = "failed"`**:
- Call `POST /internal/catalog/stock/release` for each item.
- Set `orders.status = "cancelled"`.

**Response `200`**:
```json
{
  "data": {
    "order_id": "880e8400-e29b-41d4-a716-446655440000",
    "status": "paid"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 404 | `NOT_FOUND` | Order not found |
| 409 | `CONFLICT` | Order is not in `pending` state (duplicate callback) |
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
  "service": "orders",
  "timestamp": "2025-01-01T00:00:00.000Z"
}
```

### GET /ready

**Auth**: none
**Description**: Readiness probe — returns 200 only if the database connection is healthy.

**Response `200`**:
```json
{
  "status": "ready",
  "service": "orders",
  "checks": { "database": "ok" }
}
```

**Response `503`**:
```json
{
  "status": "not_ready",
  "service": "orders",
  "checks": { "database": "error" }
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

- The cart and order entities live in the **same Orders service database** because they share the same bounded context (the customer's purchasing journey). This is not a co-location convenience — it is an intentional bounded-context decision that enables atomic transitions from cart state to order state.
- **Stock is not reserved when an item is added to the cart.** The catalog service is called only to validate product existence and active status. Stock is checked for availability (the `stock_available` flag in `GET /api/v1/cart`) but only **reserved** at checkout time. This avoids phantom out-of-stock situations where users hoard inventory by leaving items in carts indefinitely.
- `shipping_address` in the order record is a **JSONB snapshot** taken at checkout from the user's selected address. If the user later updates or deletes that address, the order retains the original shipping destination.
- `product_name` and `price_cents` in `order_items` are also **snapshots** taken at checkout. Subsequent product changes do not affect existing orders.
- `total_cents` is the sum of all `order_items.subtotal_cents`. The service computes and validates this server-side; any client-provided total is ignored.
- The `cancelled` status is terminal: a cancelled order cannot be reopened. To repurchase, the user can go back to their cart (which was preserved on payment failure) or add items again.
- The `shipped` and `delivered` statuses are set by an admin (out of scope for the automated flow in this project — included in the schema for completeness).
- All error responses follow RFC 7807 problem-details format: `{ "type": "...", "title": "...", "status": 400, "detail": "...", "correlationId": "..." }`.
- Each request includes a `correlationId` (generated at Kong and propagated via `X-Correlation-ID` header) which is included in all structured log entries and error responses for distributed tracing.
- The `user_id` stored in the order and cart is extracted from the validated JWT `sub` claim — it is never taken from the request body.
