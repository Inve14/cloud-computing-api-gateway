# Payments Service

The Payments service handles simulated payment processing for orders. It is called **internally** by the Orders service during checkout — clients never call it directly for processing. Payment outcomes are deterministic (see simulation rules in the API contract). For the full API contract see [`docs/api-contracts/payments.md`](../../docs/api-contracts/payments.md).

---

## Prerequisites

- Node.js 20 LTS
- PostgreSQL 16 (locally, or via `docker compose up -d payments-db`)
- npm (comes with Node.js)

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | no | `development` | Controls log format and dotenv loading |
| `PORT` | no | `3004` | HTTP port |
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
curl http://localhost:3004/health
curl http://localhost:3004/ready
```

---

## Running Tests

```bash
npm test
```

No real database needed — `/ready` test is skipped by default.

---

## Available Endpoints

Business routes (payment processing, history, refunds) will be added in a subsequent phase.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe |
| `GET` | `/ready` | Readiness probe — 200 if PostgreSQL responds |
| `GET` | `/metrics` | Prometheus metrics |
