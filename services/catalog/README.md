# Catalog Service

The Catalog service manages the product catalog, category taxonomy, and stock levels for the e-commerce platform. It is read-heavy: public product browsing queries are routed to a PostgreSQL read-replica, while admin writes and stock operations go to the master. The service exposes public read endpoints (no auth), admin write endpoints (JWT, `role=admin`), and internal stock/lookup endpoints consumed by the Orders service during checkout.

For the full API contract see [`docs/api-contracts/catalog.md`](../../docs/api-contracts/catalog.md).

---

## Prerequisites

- Node.js 20 LTS
- PostgreSQL 16 (locally, or via `docker compose up -d catalog-db`)
- npm (comes with Node.js)

---

## Environment Variables

All variables are documented with comments in [`.env.example`](.env.example).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | no | `development` | Controls log format and dotenv loading |
| `PORT` | no | `3001` | HTTP port |
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
# 1. Install dependencies
npm install

# 2. Create your local .env
cp .env.example .env
# Edit .env with your local PostgreSQL credentials

# 3. Start in watch mode (restarts on file changes)
npm run dev

# 4. Verify the service is up
curl http://localhost:3001/health
curl http://localhost:3001/ready
```

---

## Running Tests

```bash
npm test
```

The test suite uses Node's built-in `node:test` runner and Fastify's `inject()` method — no real database or network is needed for the currently implemented tests.

The `/ready` test (which requires PostgreSQL) is skipped by default. To run it, start a real database and set `DATABASE_URL` before running `npm test`.

---

## Available Endpoints

These are the infrastructure endpoints implemented in this scaffolding. Business routes (products, categories, stock management) will be added in a subsequent phase.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe — always 200 if the process is up |
| `GET` | `/ready` | Readiness probe — 200 if PostgreSQL responds |
| `GET` | `/metrics` | Prometheus metrics (not exposed via Kong externally) |
