# Payments API Contract

## Overview

The Payments service processes payment transactions for orders. It is a **simulated payment processor** — it does not integrate with any real payment provider (Stripe, PayPal, etc.). Payment outcomes are **deterministic** based on the input, making the service suitable for demo and fault-tolerance testing.

The service exposes:
- **Public endpoints** (via Kong): status lookup, payment history, and admin refunds.
- **Internal endpoints** (Docker network only): payment processing, called by the Orders service during checkout.

All payment operations are written to a **dedicated audit log stream** (separate from the application log) for security traceability.

## Base URL

`/api/v1/payments`

## Authentication

All public endpoints require a `Bearer` token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

The token is an RS256-signed JWT issued by the Users service. The Payments service validates it against the Users service public key (distributed via Kong configuration).

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

## Simulation Rules

This service is deterministic by design. The following rules govern payment outcomes:

| Payment method | Condition | Outcome |
|---------------|-----------|---------|
| `credit_card` | `card_number_last4 = "0000"` | **Always fails** — used for fault-tolerance demos |
| `credit_card` | any other `card_number_last4` | Succeeds after 200–500ms simulated delay |
| `paypal` | — | Always succeeds after 200–500ms simulated delay |
| `bank_transfer` | — | Always succeeds after 200–500ms simulated delay |

The simulated delay is a `setTimeout` in the service logic. In a chaos-engineering demo, the delay can be increased via an environment variable (`PAYMENT_DELAY_MS`) to trigger circuit breaker behavior at the gateway.

---

## Payment Processing Flow

The Payments service is called **internally** by the Orders service. The public-facing client never calls the Payments service directly for processing — they only use it to query status.

```
orders-service
  │
  └─ POST /internal/payments/process
       │
       ├─ 1. Validate request body
       ├─ 2. Create payment record  (status = "pending")
       ├─ 3. Apply simulation rules → determine outcome
       ├─ 4. Wait 200–500ms (simulated processing)
       ├─ 5a. Success → set status = "completed"
       │       POST /internal/orders/:orderId/payment-callback  { status: "completed" }
       └─ 5b. Failure → set status = "failed", set failure_reason
               POST /internal/orders/:orderId/payment-callback  { status: "failed", failure_reason: "..." }
```

HTTP client timeout for the callback to Orders: **3 seconds**, exponential backoff (max 3 retries).

---

## Endpoints

### GET /api/v1/payments/:paymentId

**Description**: Get a single payment record by ID. Users can only see payments where `payment.user_id` matches their JWT `sub`. Admins can see any payment.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `paymentId` | UUID | The payment ID |

**Response `200`**:
```json
{
  "data": {
    "id": "990e8400-e29b-41d4-a716-446655440000",
    "order_id": "880e8400-e29b-41d4-a716-446655440000",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "amount_cents": 8997,
    "currency": "EUR",
    "payment_method": "credit_card",
    "status": "completed",
    "transaction_reference": "TXN-2025-A3F7B2C1",
    "failure_reason": null,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.500Z"
  }
}
```

Note: `card_number_last4` is not stored or returned — only `payment_method` is persisted.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Payment belongs to a different user (non-admin) |
| 404 | `NOT_FOUND` | Payment not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/payments

**Description**: List payments for the authenticated user, paginated. Normal users see only their own payments. Admins can additionally filter by `user_id`, `order_id`, and `status`.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Query parameters**:
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `page` | integer | `1` | Page number (1-based) |
| `limit` | integer | `20` | Items per page (max 100) |
| `status` | string | — | Filter: `pending`, `completed`, `failed`, `refunded` |
| `order_id` | UUID | — | Filter by order ID |
| `user_id` | UUID | — | Admin only: filter by user |

**Response `200`**:
```json
{
  "data": [
    {
      "id": "990e8400-e29b-41d4-a716-446655440000",
      "order_id": "880e8400-e29b-41d4-a716-446655440000",
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "amount_cents": 8997,
      "currency": "EUR",
      "payment_method": "credit_card",
      "status": "completed",
      "transaction_reference": "TXN-2025-A3F7B2C1",
      "failure_reason": null,
      "created_at": "2025-01-01T00:00:00.000Z",
      "updated_at": "2025-01-01T00:00:00.500Z"
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

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Invalid query parameters |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Non-admin tried to filter by `user_id` |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/payments/:paymentId/refund

**Description**: Issue an immediate (simulated) refund for a completed payment. **Admin only** (`role = "admin"` in JWT). Only payments with `status = "completed"` can be refunded. On success, sets `status = "refunded"`. The corresponding order status is **not** automatically updated — the admin must also update the order if needed.
**Auth**: required, admin only
**Rate limit**: 10 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `paymentId` | UUID | The payment ID to refund |

**Request body**: none required.

**Response `200`**:
```json
{
  "data": {
    "id": "990e8400-e29b-41d4-a716-446655440000",
    "order_id": "880e8400-e29b-41d4-a716-446655440000",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "amount_cents": 8997,
    "currency": "EUR",
    "payment_method": "credit_card",
    "status": "refunded",
    "transaction_reference": "TXN-2025-A3F7B2C1",
    "failure_reason": null,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T10:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Caller is not an admin |
| 404 | `NOT_FOUND` | Payment not found |
| 409 | `PAYMENT_NOT_COMPLETED` | Payment status is not `completed` (e.g. already failed or refunded) |
| 429 | `RATE_LIMITED` | Too many refund requests |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

## Internal Endpoints

These endpoints are **not exposed through Kong**. They are reachable only on the internal Docker network by trusted peer services (specifically the Orders service). No JWT is required.

### POST /internal/payments/process

**Description**: Initiate payment processing for an order. Called exclusively by the Orders service during checkout. Applies simulation rules to determine the outcome, then asynchronously notifies the Orders service via the payment callback.
**Auth**: none (internal network only)

**Request body**:
```json
{
  "order_id": "880e8400-e29b-41d4-a716-446655440000",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "amount_cents": 8997,
  "currency": "EUR",
  "payment_method": "credit_card",
  "card_number_last4": "1234"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `order_id` | UUID | yes | Logical FK to orders.id |
| `user_id` | UUID | yes | Logical FK to users.id |
| `amount_cents` | integer | yes | Must be > 0 |
| `currency` | string | yes | ISO 4217 (e.g. `"EUR"`) |
| `payment_method` | string | yes | `"credit_card"`, `"paypal"`, or `"bank_transfer"` |
| `card_number_last4` | string | no | Required when `payment_method = "credit_card"` |

**Processing logic**:
1. Validate request body.
2. Create payment record with `status = "pending"` and a generated `transaction_reference` (e.g. `TXN-<timestamp>-<random>`).
3. Evaluate simulation rules:
   - `credit_card` + `card_number_last4 = "0000"` → outcome: `failed`, `failure_reason = "Card declined"`
   - All other cases → outcome: `completed` after `200–500ms` delay
4. Update payment record to final status.
5. Call `POST /internal/orders/:orderId/payment-callback` with outcome.
6. Respond to the Orders service.

**Response `200`** (returned immediately after creating the pending record, before simulation completes — callback delivers the final status):

> **Note**: for simplicity in this project, the response is **synchronous** — the service applies the simulation delay inline and responds with the final status. The callback is also sent. This makes the checkout flow straightforward to reason about during demos.

```json
{
  "data": {
    "payment_id": "990e8400-e29b-41d4-a716-446655440000",
    "status": "completed",
    "transaction_reference": "TXN-2025-A3F7B2C1",
    "failure_reason": null
  }
}
```

```json
{
  "data": {
    "payment_id": "990e8400-e29b-41d4-a716-446655440001",
    "status": "failed",
    "transaction_reference": "TXN-2025-D4E8F1A0",
    "failure_reason": "Card declined"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 409 | `CONFLICT` | A payment for this `order_id` already exists |
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
  "service": "payments",
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
  "service": "payments",
  "checks": { "database": "ok" }
}
```

**Response `503`**:
```json
{
  "status": "not_ready",
  "service": "payments",
  "checks": { "database": "error" }
}
```

---

## Rate Limiting

Applied by Kong at the gateway level.

| Endpoint | Limit |
|----------|-------|
| `POST /api/v1/payments/:paymentId/refund` | 10 req/min per IP |
| All other public endpoints | 100 req/min per IP |

Rate limit exceeded responses return HTTP 429 with error code `RATE_LIMITED`.

---

## Notes

- `card_number_last4` is accepted by the internal endpoint for simulation purposes only. It is **never stored** in the database — the `payment_method` field records the method, not the card details.
- `transaction_reference` is a generated mock ID (e.g. `TXN-<ISO-date>-<8-char-random>`). It is unique per payment and can be used as a correlation handle between orders and payments in logs.
- `failure_reason` is only populated when `status = "failed"`. It is a human-readable string for display/debug purposes (e.g. `"Card declined"`, `"Insufficient funds"`).
- The refund flow does **not** notify the Orders service or change the order status. An admin-initiated refund is assumed to be handled out-of-band (e.g. manually updating the order or triggering a separate compensation). This is acceptable for the project scope.
- All payment operations (process initiated, completed, failed, refunded) are written to a **dedicated audit log** stream. The audit log is a separate pino stream writing to a dedicated file or stdout label (`audit`), distinct from the application log.
- The simulated delay (`200–500ms`) is controlled by the `PAYMENT_DELAY_MS_MIN` and `PAYMENT_DELAY_MS_MAX` environment variables. Setting `PAYMENT_DELAY_MS_MIN=5000` in a chaos demo will reliably trigger Kong's upstream timeout and circuit breaker.
- There is exactly **one payment per order**. The `CONFLICT` error on `POST /internal/payments/process` prevents duplicate processing if the Orders service retries the call.
- All error responses follow RFC 7807 problem-details format: `{ "type": "...", "title": "...", "status": 400, "detail": "...", "correlationId": "..." }`.
- Each request includes a `correlationId` propagated via `X-Correlation-ID` header (set by Kong, forwarded by all services) and included in all structured log entries.
