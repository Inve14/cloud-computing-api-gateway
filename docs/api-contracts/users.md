# Users API Contract

## Overview

The Users service manages user accounts, authentication, and address books. It is the **sole issuer of JWT tokens** in the system — all other services consume tokens issued here but never mint them.

Authentication uses **RS256 asymmetric JWT**: the Users service holds the RSA private key and signs tokens; Kong and other services hold the public key for verification only.

## Base URL

`/api/v1/users`

## Authentication

All protected endpoints require a `Bearer` token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

Tokens are RS256-signed JWTs with the following payload:

```json
{
  "sub": "<user-uuid>",
  "email": "user@example.com",
  "role": "customer",
  "iat": 1700000000,
  "exp": 1700000900
}
```

Access tokens expire after **15 minutes**. Use `POST /api/v1/users/auth/refresh` to obtain a new one without re-authenticating.

---

## Endpoints

### POST /api/v1/users/auth/register

**Description**: Register a new user account.
**Auth**: none
**Rate limit**: 10 req/min per IP

**Request body**:
```json
{
  "email": "user@example.com",
  "password": "S3cure!Pass",
  "first_name": "Mario",
  "last_name": "Rossi",
  "phone": "+393331234567"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `email` | string | yes | Valid email, max 254 chars |
| `password` | string | yes | Min 8 chars |
| `first_name` | string | yes | Max 100 chars |
| `last_name` | string | yes | Max 100 chars |
| `phone` | string | no | E.164 format |

**Response `201`**:
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "first_name": "Mario",
    "last_name": "Rossi",
    "phone": "+393331234567",
    "role": "customer",
    "is_verified": false,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 409 | `EMAIL_ALREADY_EXISTS` | A user with this email already exists |
| 429 | `RATE_LIMITED` | Too many registration attempts |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/users/auth/login

**Description**: Authenticate with email and password. Issues an access token and a refresh token. Every attempt (success or failure) is written to the audit log.
**Auth**: none
**Rate limit**: 10 req/min per IP

**Request body**:
```json
{
  "email": "user@example.com",
  "password": "S3cure!Pass"
}
```

**Response `200`**:
```json
{
  "data": {
    "access_token": "<jwt>",
    "refresh_token": "<opaque-string>",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

| Field | Description |
|-------|-------------|
| `access_token` | RS256 JWT, valid 15 minutes |
| `refresh_token` | Opaque string, valid 7 days |
| `expires_in` | Seconds until access_token expiry |

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing or malformed fields |
| 401 | `INVALID_CREDENTIALS` | Email not found or password incorrect |
| 429 | `RATE_LIMITED` | Too many login attempts from this IP |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/users/auth/refresh

**Description**: Exchange a valid refresh token for a new access token. The refresh token itself remains valid until its 7-day expiry.
**Auth**: none (refresh token in body)
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "refresh_token": "<opaque-string>"
}
```

**Response `200`**:
```json
{
  "data": {
    "access_token": "<jwt>",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing refresh_token field |
| 401 | `TOKEN_EXPIRED` | Refresh token has expired |
| 401 | `TOKEN_INVALID` | Refresh token not found or already invalidated |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/users/auth/logout

**Description**: Invalidate the current refresh token. The access token remains valid until its natural expiry (15 min) — clients should discard it locally.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "refresh_token": "<opaque-string>"
}
```

**Response `204`**: no body.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Missing refresh_token field |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/users/me

**Description**: Return the authenticated user's profile.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Response `200`**:
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "first_name": "Mario",
    "last_name": "Rossi",
    "phone": "+393331234567",
    "role": "customer",
    "is_verified": false,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### PATCH /api/v1/users/me

**Description**: Update the authenticated user's profile. Only `first_name`, `last_name`, and `phone` are mutable. Email and role changes are out of scope.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Request body** (all fields optional; at least one required):
```json
{
  "first_name": "Mario",
  "last_name": "Bianchi",
  "phone": "+393337654321"
}
```

**Response `200`**:
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "first_name": "Mario",
    "last_name": "Bianchi",
    "phone": "+393337654321",
    "role": "customer",
    "is_verified": false,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T12:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Malformed fields or empty body |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/users/me/addresses

**Description**: List all addresses (shipping and billing) for the authenticated user.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Response `200`**:
```json
{
  "data": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "shipping",
      "street": "Via Roma 1",
      "city": "Milano",
      "zip_code": "20100",
      "country": "IT",
      "is_default": true,
      "created_at": "2025-01-01T00:00:00.000Z",
      "updated_at": "2025-01-01T00:00:00.000Z"
    }
  ]
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### POST /api/v1/users/me/addresses

**Description**: Create a new address for the authenticated user. If `is_default: true` is set and another address of the same `type` already has `is_default = true`, the old one is unset atomically.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Request body**:
```json
{
  "type": "shipping",
  "street": "Via Roma 1",
  "city": "Milano",
  "zip_code": "20100",
  "country": "IT",
  "is_default": true
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `type` | string | yes | `"shipping"` or `"billing"` |
| `street` | string | yes | Max 200 chars |
| `city` | string | yes | Max 100 chars |
| `zip_code` | string | yes | Max 20 chars |
| `country` | string | no | ISO 3166-1 alpha-2, default `"IT"` |
| `is_default` | boolean | no | Default `false` |

**Response `201`**:
```json
{
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440002",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "shipping",
    "street": "Via Roma 1",
    "city": "Milano",
    "zip_code": "20100",
    "country": "IT",
    "is_default": true,
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
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### GET /api/v1/users/me/addresses/:addressId

**Description**: Get a single address by ID. Returns 403 if the address belongs to a different user.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `addressId` | UUID | The address ID |

**Response `200`**:
```json
{
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "shipping",
    "street": "Via Roma 1",
    "city": "Milano",
    "zip_code": "20100",
    "country": "IT",
    "is_default": true,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T00:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Address belongs to a different user |
| 404 | `NOT_FOUND` | Address not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### PATCH /api/v1/users/me/addresses/:addressId

**Description**: Update an existing address. All fields optional; at least one required. Ownership check: 403 if address belongs to a different user. If `is_default: true` is set, the old default of the same type is unset atomically.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `addressId` | UUID | The address ID |

**Request body** (all fields optional):
```json
{
  "street": "Via Garibaldi 10",
  "city": "Torino",
  "zip_code": "10100",
  "country": "IT",
  "is_default": false
}
```

**Response `200`**:
```json
{
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "shipping",
    "street": "Via Garibaldi 10",
    "city": "Torino",
    "zip_code": "10100",
    "country": "IT",
    "is_default": false,
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-01T12:00:00.000Z"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Malformed fields or empty body |
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Address belongs to a different user |
| 404 | `NOT_FOUND` | Address not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

### DELETE /api/v1/users/me/addresses/:addressId

**Description**: Delete an address. Ownership check: 403 if address belongs to a different user.
**Auth**: required
**Rate limit**: 100 req/min per IP

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `addressId` | UUID | The address ID |

**Response `204`**: no body.

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 401 | `UNAUTHORIZED` | Missing or invalid access token |
| 403 | `FORBIDDEN` | Address belongs to a different user |
| 404 | `NOT_FOUND` | Address not found |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

---

## Internal Endpoints

These endpoints are **not exposed through Kong**. They are reachable only on the internal Docker network by trusted peer services.

### GET /internal/users/:userId

**Description**: Validate that a user exists and return minimal profile data. Called by the orders and payments services before creating records that reference a user_id.
**Auth**: none (internal network only — no JWT required)

**Path parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `userId` | UUID | The user ID to look up |

**Response `200`**:
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "role": "customer"
  }
}
```

**Errors**:
| Status | Code | Description |
|--------|------|-------------|
| 404 | `NOT_FOUND` | User not found |
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
  "service": "users",
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
  "service": "users",
  "checks": { "database": "ok" }
}
```

**Response `503`**:
```json
{
  "status": "not_ready",
  "service": "users",
  "checks": { "database": "error" }
}
```

---

## Rate Limiting

Applied by Kong at the gateway level.

| Endpoint | Limit |
|----------|-------|
| `POST /api/v1/users/auth/login` | 10 req/min per IP |
| `POST /api/v1/users/auth/register` | 10 req/min per IP |
| All other endpoints | 100 req/min per IP |

Rate limit exceeded responses return HTTP 429 with error code `RATE_LIMITED`.

---

## Notes

- `password_hash` is never included in any API response. Plaintext passwords are never logged.
- Passwords are hashed with bcrypt, cost factor 12. Minimum length enforced at application level (8 chars); additional complexity rules may be added without breaking this contract.
- The `role` field in the JWT payload is the authoritative source for authorization checks across all services. It is embedded at login time; a role change takes effect only after the current access token expires.
- Refresh tokens are opaque strings (UUID v4 or similar), stored hashed in the database. They are invalidated on logout. There is no refresh token rotation in the current scope.
- `is_verified` is set to `false` at registration. Email verification flow is out of scope for this project; the field is reserved for future use.
- All security-relevant events (login success, login failure, logout, token refresh) are written to a dedicated audit log stream (structured JSON, separate from the application log).
- `type` on an address cannot be changed via PATCH — to change type, delete and recreate.
- Only one address per `(user_id, type)` can have `is_default = true`. Enforced in application logic, not at DB level.
- All error responses follow RFC 7807 problem-details format: `{ "type": "...", "title": "...", "status": 400, "detail": "...", "correlationId": "..." }`.
