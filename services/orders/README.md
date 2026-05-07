# Orders Service

The Orders service owns the entire purchasing journey: shopping cart management, checkout, and order lifecycle. It orchestrates calls to the catalog service (product validation + stock reservation) and the payments service during checkout. For the full API contract see [`docs/api-contracts/orders.md`](../../docs/api-contracts/orders.md).

---

## Prerequisites

- Node.js 20 LTS
- PostgreSQL 16 (locally, or via `docker compose up -d orders-db`)
- npm (comes with Node.js)

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | no | `development` | Controls log format and dotenv loading |
| `PORT` | no | `3003` | HTTP port |
| `LOG_LEVEL` | no | `info` | Pino log level |
| `DATABASE_URL` | yes* | — | Full PostgreSQL connection string |
| `DB_HOST` | yes* | — | Alternative to DATABASE_URL |
| `DB_PORT` | no | `5432` | |
| `DB_NAME` | yes* | — | |
| `DB_USER` | yes* | — | |
| `DB_PASSWORD` | yes* | — | |
| `DB_POOL_MAX` | no | `10` | Max pool connections per replica |
| `DB_IDLE_TIMEOUT_MS` | no | `30000` | |
| `DB_CONNECTION_TIMEOUT_MS` | no | `3000` | |

\* Either `DATABASE_URL` **or** all four `DB_*` variables must be provided.

---

## Running Locally

```bash
npm install
cp .env.example .env   # edit with local PostgreSQL credentials
npm run dev
curl http://localhost:3003/health
curl http://localhost:3003/ready
```

---

## Running Tests

```bash
npm test
```

No real database needed — `/ready` test is skipped by default.

---

## Available Endpoints

Business routes (cart, checkout, orders CRUD) will be added in a subsequent phase.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe |
| `GET` | `/ready` | Readiness probe — 200 if PostgreSQL responds |
| `GET` | `/metrics` | Prometheus metrics |
