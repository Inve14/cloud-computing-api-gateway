# Users Service

The Users service manages user accounts, authentication, and address management. It is the **sole JWT issuer** in the system — all tokens are RS256-signed here; Kong and peer services only verify them. For the full API contract see [`docs/api-contracts/users.md`](../../docs/api-contracts/users.md).

---

## Prerequisites

- Node.js 20 LTS
- PostgreSQL 16 (locally, or via `docker compose up -d users-db`)
- npm (comes with Node.js)

---

## Environment Variables

All variables are documented with comments in [`.env.example`](.env.example).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | no | `development` | Controls log format and dotenv loading |
| `PORT` | no | `3002` | HTTP port |
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
curl http://localhost:3002/health
curl http://localhost:3002/ready
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

These are the infrastructure endpoints implemented in this scaffolding. Business routes (auth, profile, addresses) will be added in a subsequent phase.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe — always 200 if the process is up |
| `GET` | `/ready` | Readiness probe — 200 if PostgreSQL responds |
| `GET` | `/metrics` | Prometheus metrics (not exposed via Kong externally) |
