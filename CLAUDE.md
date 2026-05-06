# CLAUDE.md

This file provides project-wide context for Claude Code. Read it before any task in this repository.

## Project Overview

This is a university project for the **Cloud Computing and Technologies** course.
The project implements a **mini e-commerce application** using a **microservices architecture** with an **API Gateway** as the single entry point, **deployed on AWS EC2**.

The project was approved by the professor with explicit emphasis on the following requirements (since it is a two-person project):
- **Resilience**: graceful handling of failures, no single point of failure for business services.
- **Security** (mentioned twice by the professor): HTTPS, strong JWT, rate limiting, secrets management, input validation.
- **Replication**: multiple replicas of every business component, plus database replication where feasible.
- **Articulated cloud deployment**: the system runs on a real AWS EC2 VM (not just localhost), with automated provisioning, HTTPS via Let's Encrypt, and a CI/CD pipeline.

This project is developed by **two students** and must show meaningful complexity beyond a single-person submission.

## Architecture

The system is composed of:

### Business microservices (4)
- **catalog**: product catalog, search, stock management. Read-heavy, ideal for load balancing demos.
- **users**: registration, authentication, profile management. Issues JWT tokens (RS256).
- **orders**: shopping cart and order management. Owns the entire purchasing flow (cart, checkout, order lifecycle). Calls catalog (stock check/reserve) and payments (checkout). Cart lives in the same database as orders — they share the same bounded context.
- **payments**: simulated payment processing. Used to demonstrate retry/fallback patterns.

### Infrastructure (in-VM)
- **Kong API Gateway** (community edition, 2 replicas): single entry point. Handles HTTPS termination, routing, JWT validation, rate limiting, load balancing across microservice replicas, circuit breaker, and metrics export.
- **Consul**: service discovery for dynamic registration of microservice instances.
- **Prometheus**: metrics collection from Kong and microservices.
- **Grafana**: dashboards for observability and exam demos.
- **PostgreSQL**: one database per microservice (database-per-service pattern). The `catalog` database has master + read-replica setup; the others are single-node for simplicity.

### Deployment
- **Target**: AWS EC2 VM (Ubuntu 22.04 LTS, t3.medium or t3.large).
- **Provisioning**: automated via cloud-init bootstrap script.
- **HTTPS**: Let's Encrypt certificate, auto-renewed via certbot.
- **DNS**: free subdomain (DuckDNS or nip.io) pointing to the EC2 public IP.
- **Firewall**: AWS Security Group allows only ports 22 (SSH, restricted by IP), 80 (HTTP, redirect to 443), 443 (HTTPS).
- **CI/CD**: GitHub Actions pipeline deploys on push to `main` via SSH.
- **Backup**: scheduled snapshots of Docker volumes (database data) via cron.

### Communication
- External clients communicate **only** with Kong over HTTPS (services are not exposed directly).
- Services communicate with each other via internal Docker network, discovered via Consul.
- All inter-service authentication uses JWT tokens issued by `users`.

## Tech Stack

- **Cloud provider**: AWS (free tier + GitHub Student Developer Pack credits)
- **Runtime**: Node.js 20 LTS
- **Web framework**: Fastify (performance + built-in JSON Schema validation)
- **Database**: PostgreSQL 16 (catalog DB: master + read-replica via streaming replication)
- **ORM/Query builder**: Prisma (preferred) or Knex.js as fallback
- **API Gateway**: Kong 3.x community edition (declarative config via `kong.yml`)
- **Service discovery**: Consul (latest)
- **Monitoring**: Prometheus + Grafana (latest)
- **Container orchestration**: Docker Compose
- **Load testing**: k6
- **API testing during development**: Bruno
- **Authentication**: JWT (RS256, asymmetric keys)
- **Password hashing**: bcrypt (cost factor 12)
- **HTTPS in production**: Let's Encrypt + certbot
- **HTTPS in local dev**: mkcert self-signed certs
- **CI/CD**: GitHub Actions

## Project Structure
cloud-computing-api-gateway/
├── services/
│   ├── catalog/         # Catalog microservice
│   ├── users/           # Users microservice
│   ├── orders/          # Orders microservice
│   └── payments/        # Payments microservice
├── infrastructure/
│   ├── kong/            # Kong declarative config and plugins
│   ├── consul/          # Consul configuration
│   └── monitoring/      # Prometheus config, Grafana dashboards
├── deployment/          # NEW: cloud deployment artifacts
│   ├── aws/             # cloud-init scripts, security group definitions
│   ├── ci-cd/           # GitHub Actions workflows
│   └── ssl/             # certbot config and renewal scripts
├── docs/
│   ├── api-contracts/   # OpenAPI specs for each service
│   ├── architecture/    # Architecture decision records, diagrams
│   └── demos/           # Scripts and notes for exam demos
├── scripts/
│   ├── load-tests/      # k6 scripts for load testing demos
│   └── chaos/           # Scripts to simulate failures
├── docker-compose.yml         # Main orchestration file (production)
├── docker-compose.dev.yml     # Local development override
├── README.md            # Public-facing documentation
└── CLAUDE.md            # This file

Each microservice in `services/` follows the same internal structure:
services/<name>/
├── src/
│   ├── routes/          # HTTP route handlers
│   ├── services/        # Business logic
│   ├── repositories/    # Database access layer
│   ├── schemas/         # JSON schema definitions
│   └── server.js        # Fastify entry point
├── tests/               # Unit and integration tests
├── Dockerfile
├── package.json
└── README.md            # Service-specific documentation

## Coding Conventions

- **Language**: all code, comments, commit messages, and technical documentation in **English**.
- **Style**: ESLint with `@eslint/js` recommended config + Prettier defaults. 2-space indentation.
- **Naming**: `camelCase` for variables and functions, `PascalCase` for classes, `kebab-case` for filenames and Docker service names, `SCREAMING_SNAKE_CASE` for environment variables.
- **HTTP endpoints**: RESTful, plural nouns (`/products` not `/product`), versioned under `/api/v1/...`.
- **Error handling**: never swallow errors silently. Always log with structured JSON logging (use `pino`). Return RFC 7807 problem-details JSON for HTTP errors.
- **Logging**: structured JSON, level-based (`info`, `warn`, `error`). Include `correlationId` for request tracing across services.
- **Configuration**: all config via environment variables, loaded with `dotenv` only in development. Never hardcode secrets, ports, or URLs.
- **Health endpoints**: every service must expose `GET /health` (liveness) and `GET /ready` (readiness, checks database connection).
- **Metrics endpoint**: every service must expose `GET /metrics` in Prometheus format (use `prom-client`).

## Non-Functional Requirements

Every change must respect these requirements; flag any tradeoff explicitly. The professor will evaluate the project primarily based on these properties.

### Resilience (fault tolerance + high availability)
- Every container has a `healthcheck` directive in `docker-compose.yml`.
- Restart policy: `unless-stopped` for all services.
- HTTP clients between services must use timeouts (default 3s) and retry with exponential backoff (max 3 retries).
- Kong upstream health checks (active + passive) must be configured for every service.
- Circuit breaker: implemented at gateway level via Kong plugins where possible, otherwise via `opossum` library.
- Business services run with **at least 2 replicas** (catalog: 3, users/orders/payments: 2).
- **Kong itself runs with 2 replicas** for gateway-level high availability.
- `depends_on` with `condition: service_healthy` ensures correct startup order.
- Graceful shutdown: services must handle SIGTERM and finish in-flight requests before exiting.
- The catalog database uses **PostgreSQL streaming replication** (1 master + 1 read-replica).

### Replication
- Service replicas defined explicitly in `docker-compose.yml` via `deploy.replicas` or `--scale` at runtime.
- All services must be **stateless**: no in-memory sessions, no local file writes — required to support replication.
- Database connections use a pool (default 10 connections per replica).
- Read-heavy queries on catalog must hit the read-replica, not the master.

### Security
- **HTTPS everywhere**: Let's Encrypt in production, self-signed via mkcert in local dev. HTTP redirected to HTTPS.
- **JWT validation** enforced at Kong via the `jwt` plugin. Use RS256 (asymmetric); the `users` service holds the private key, Kong holds the public key.
- **Passwords** stored as bcrypt hashes (cost factor 12).
- **Rate limiting** at Kong: aggressive on `/auth/login` and `/payments/*` (10 req/min per IP), looser on read endpoints (100 req/min per IP).
- **Input validation** rigorous on every endpoint via Fastify's JSON Schema integration.
- **Secrets management**: never commit `.env` files. Use `.env.example` for templates. In production, secrets injected via environment variables at deploy time.
- **Network isolation**: only Kong is exposed externally. Microservices and databases are reachable only from the internal Docker network.
- **AWS Security Group**: only ports 22 (SSH from developer IPs), 80, 443 open.
- **Audit logging**: dedicated structured log stream for security-relevant events (login attempts, order modifications, payment operations).

### Observability
- All services expose Prometheus metrics on `/metrics`.
- Grafana dashboards include: request rate per service, error rate, p50/p95/p99 latency, active connections, JVM/Node memory.
- Alert rules configured for: service down, error rate >5%, p99 latency >1s.

## Subagent Routing Rules

When delegating work, Claude should follow these rules.

### Parallel dispatch (use multiple subagents simultaneously)
ALL of these conditions must be met:
- 3+ unrelated tasks targeting different microservices or different infrastructure components.
- No shared state or shared files between tasks.
- Clear file boundaries (e.g., one subagent works only inside `services/catalog/`, another only inside `services/users/`).

Examples of valid parallel dispatch:
- "Generate the scaffolding for catalog, users, orders, and payments simultaneously."
- "Investigate logs from each microservice in parallel to identify the failure source."

### Sequential dispatch (use subagents one at a time)
ANY of these conditions triggers sequential mode:
- Tasks have dependencies (e.g., orders implementation depends on catalog API contract).
- Multiple tasks would modify `docker-compose.yml`, `kong.yml`, or any shared config file.
- The scope is unclear and exploration is required first.

### Background dispatch
- Use for read-only research or analysis tasks (e.g., "summarize current Kong configuration").
- Never for file modifications.

## Commands & Workflows

### Local development
```bash
# Start the entire stack (uses dev override with self-signed certs)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Scale a specific service to N replicas
docker compose up -d --scale catalog=3

# Tail logs from a specific service
docker compose logs -f catalog

# Stop and remove everything
docker compose down -v
```

### Cloud deployment (AWS EC2)
```bash
# Initial provisioning (run once on a new EC2 instance)
bash deployment/aws/bootstrap.sh

# Deploy latest code to the EC2 VM
git push origin main          # triggers GitHub Actions, which SSHes into the VM and pulls + restarts

# Manual deploy (if CI/CD is down)
ssh ec2-user@<vm-ip> 'cd /opt/app && git pull && docker compose up -d --build'

# Renew SSL certificate manually (auto-renewed by cron normally)
ssh ec2-user@<vm-ip> 'sudo certbot renew && docker compose restart kong'
```

### Testing a single microservice in isolation
```bash
cd services/<name>
npm install
npm run dev          # starts Fastify in watch mode
npm test             # runs tests
```

### Load testing
```bash
# Local
k6 run scripts/load-tests/<scenario>.js

# Against the cloud deployment
k6 run -e BASE_URL=https://<your-domain> scripts/load-tests/<scenario>.js
```

### Simulating failures (chaos engineering demos)
```bash
# Kill a random catalog instance
bash scripts/chaos/kill-random-catalog.sh

# Bring down all payments instances
bash scripts/chaos/kill-all-payments.sh

# Simulate database master failure
bash scripts/chaos/kill-catalog-db-master.sh
```

## Important Notes

### Things Claude must NEVER do without explicit confirmation
- Modify `docker-compose.yml` without explaining the impact on the running stack.
- Change Kong declarative config (`kong.yml`) without confirming routing rules.
- Add new top-level dependencies (e.g., switch from Fastify to Express) — these decisions are made by the humans.
- Commit `.env` files or any file containing secrets.
- Push directly to `main` — always work on a feature branch and let the user open the PR.
- Modify AWS infrastructure (Security Groups, EC2 settings) without explicit approval.

### Things Claude should always do
- Before generating code, look at existing services for patterns. We want consistency, not novelty.
- When adding a new endpoint, also add the corresponding entry to the service's OpenAPI spec in `docs/api-contracts/`.
- When modifying a service, verify that the existing tests still pass before declaring the task done.
- When generating a Dockerfile, use multi-stage builds, run as non-root user, and pin base image versions (no `:latest` tags).
- When working on security-relevant code (auth, JWT, password handling), be extra cautious and reference OWASP best practices.

### Academic context
- This is a **graded university project** developed in pairs.
- The professor will grade based on:
  1. Code quality and consistency.
  2. Correct demonstration of resilience, security, replication, and articulated cloud deployment.
  3. Quality of the `docker-compose.yml` file (this is a major focus per past students' feedback).
  4. Live demos during oral examination.
- Both students must understand every part of the system; avoid generating opaque "magic" code.
- The professor explicitly mentioned that since this is a two-person project, the bar is higher than a solo submission.

### Out of scope (do NOT implement)
- Real payment integration (Stripe, PayPal, etc.) — payments are simulated with deterministic responses.
- Frontend / UI — the project is backend-only. APIs are tested via Bruno during development.
- Production-grade Kubernetes deployment — Docker Compose on a single EC2 VM is sufficient.
- Multi-region deployment — single-region only (likely `eu-south-1` Milan or `eu-west-1` Ireland).
- AWS managed services (RDS, ElastiCache, ELB) — would burn through free credits unnecessarily; everything runs as Docker containers on the VM.