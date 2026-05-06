# Cloud Computing Project — API Gateway

A mini e-commerce application built on a **microservices architecture** with an **API Gateway** as the single entry point. Designed to demonstrate four key non-functional properties: **resilience**, **security**, **replication**, and **articulated cloud deployment**.

University project for the *Cloud Computing and Technologies* course.

---

## Project status

🟢 **Phase 1: Planning** — Completed
🟡 **Phase 2: Local development** — In progress
⚪ **Phase 3: Cloud deployment** — Not started
⚪ **Phase 4: Demo preparation** — Not started

---

## Architecture

The system is composed of **4 business microservices** behind a single **Kong API Gateway**, deployed on an **AWS EC2 VM** with end-to-end HTTPS.

```
                            ┌──────────────┐
                            │   Client     │
                            └──────┬───────┘
                                   │ HTTPS
                                   ▼
                       ┌────────────────────────┐
                       │   Kong API Gateway     │  (×2 replicas)
                       │  JWT, rate limit, LB   │
                       └───────────┬────────────┘
                                   │
              ┌──────────┬─────────┼──────────┬──────────┐
              ▼          ▼         ▼          ▼          ▼
         ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────┐
         │catalog │ │ users  │ │ orders │ │  payments  │
         │  ×3    │ │  ×2    │ │  ×2    │ │    ×2      │
         └───┬────┘ └───┬────┘ └───┬────┘ └─────┬──────┘
             │          │          │            │
             ▼          ▼          ▼            ▼
         ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────┐
         │catalog │ │ users  │ │ orders │ │  payments  │
         │  DB    │ │  DB    │ │  DB    │ │    DB      │
         │master+ │ │ single │ │ single │ │   single   │
         │replica │ │  node  │ │  node  │ │    node    │
         └────────┘ └────────┘ └────────┘ └────────────┘
```

### Microservices

| Service | Purpose | Replicas |
|---------|---------|----------|
| **catalog** | Product catalog, search, stock management | 3 |
| **users** | Registration, authentication (JWT RS256), profiles, addresses | 2 |
| **orders** | Shopping cart, checkout, order lifecycle | 2 |
| **payments** | Simulated payment processing | 2 |

### Supporting infrastructure

| Component | Purpose |
|-----------|---------|
| **Kong API Gateway** (×2) | Entry point: routing, JWT validation, rate limiting, load balancing, circuit breaker |
| **Consul** | Dynamic service discovery |
| **Prometheus** | Metrics collection |
| **Grafana** | Observability dashboards |
| **PostgreSQL** | Per-service databases (catalog: master + read-replica) |

---

## Tech stack

- **Runtime**: Node.js 20 LTS
- **Web framework**: Fastify (with built-in JSON Schema validation)
- **Database**: PostgreSQL 16
- **API Gateway**: Kong 3.x (community edition)
- **Service discovery**: Consul
- **Monitoring**: Prometheus + Grafana
- **Container orchestration**: Docker Compose
- **Cloud provider**: AWS EC2 (Ubuntu 22.04 LTS)
- **CI/CD**: GitHub Actions
- **HTTPS**: Let's Encrypt (production), mkcert (local development)
- **Load testing**: k6

---

## Project structure

```
cloud-computing-api-gateway/
├── services/                # Business microservices
│   ├── catalog/
│   ├── users/
│   ├── orders/
│   └── payments/
├── infrastructure/          # Application infrastructure
│   ├── kong/                # Kong declarative config
│   ├── consul/              # Service discovery config
│   └── monitoring/          # Prometheus + Grafana
├── deployment/              # Cloud deployment artifacts
│   ├── aws/                 # Cloud-init bootstrap, security groups
│   ├── ci-cd/               # GitHub Actions workflows
│   └── ssl/                 # Certbot config
├── docs/                    # Documentation
│   ├── api-contracts/       # API contracts per service
│   ├── architecture/        # Database schema, ADRs
│   └── demos/               # Exam demo scripts
├── scripts/                 # Utility scripts
│   ├── load-tests/          # k6 load test scenarios
│   └── chaos/               # Failure simulation scripts
├── docker-compose.yml       # Production orchestration
├── docker-compose.dev.yml   # Local development overrides
├── README.md                # This file
└── CLAUDE.md                # Project context for Claude Code
```

---

## Non-functional properties

This project is explicitly designed around four properties, as specified by the course professor:

### 🛡️ Resilience
- 2–3 replicas per business service; Kong itself replicated ×2
- Healthchecks and automatic restart policies on every container
- HTTP retries with exponential backoff between services
- Circuit breaker at the gateway level (Kong plugins)
- Graceful degradation: if payments is down, browsing and login still work

### 🔒 Security
- HTTPS end-to-end (Let's Encrypt in production)
- JWT with **RS256** asymmetric signing (users service signs, Kong verifies)
- bcrypt with cost factor 12 for password hashing
- Rate limiting differentiated per endpoint sensitivity (10 req/min for login, 100 req/min for browsing)
- Strict input validation via JSON Schema
- Dedicated audit logging for security-relevant events
- Network isolation: only Kong is publicly exposed
- Restrictive AWS Security Group (ports 22, 80, 443 only)

### 🔁 Replication
- Microservice replicas managed declaratively in `docker-compose.yml`
- All services are stateless to allow horizontal scaling
- Catalog database with **PostgreSQL streaming replication** (master + read-replica)
- Read-heavy queries routed to the replica, writes to the master

### ☁️ Articulated cloud deployment
- AWS EC2 VM with automated provisioning via cloud-init script
- Real HTTPS via Let's Encrypt + free domain (DuckDNS)
- CI/CD pipeline with GitHub Actions: deploy on push to `main`
- Scheduled backups of database volumes
- Reproducible environment from scratch

---

## Documentation

Detailed planning artifacts are available in the `docs/` directory:

- 📊 [Database schema](./docs/architecture/database-schema.md) — entity-relationship and table definitions for each service
- 🌐 API contracts:
  - [catalog](./docs/api-contracts/catalog.md)
  - [users](./docs/api-contracts/users.md)
  - [orders](./docs/api-contracts/orders.md) (includes shopping cart endpoints)
  - [payments](./docs/api-contracts/payments.md)
- 🤖 [CLAUDE.md](./CLAUDE.md) — project-wide context, conventions, and routing rules for Claude Code

---

## Setup and run

> ⚠️ **Note**: this section will be completed during Phase 2 (local development). The `docker-compose.yml` is not yet implemented.

### Prerequisites (planned)
- Docker Desktop (with Docker Compose)
- Node.js 20 LTS
- Bruno or Postman (for API testing)

### Local development (planned)
```bash
# Start the entire stack
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Scale a service to N replicas
docker compose up -d --scale catalog=3

# View logs
docker compose logs -f catalog

# Stop everything
docker compose down -v
```

### Cloud deployment (planned)
Deployment to AWS EC2 happens automatically via GitHub Actions on push to `main`. Manual deployment instructions will be documented here.

---

## Demos planned for the oral examination

Three live demos on the cloud-deployed VM, each targeting one of the non-functional properties:

1. **Resilience and replication** — Generate load with k6, kill a service replica during the test, observe automatic recovery and traffic redistribution.
2. **Security** — Demonstrate JWT validation, rate limiting, and audit logging on protected endpoints.
3. **Graceful degradation** — Bring down the payments service entirely; show that browsing, login, and cart operations continue to work, while checkout returns a controlled error.

---

## Authors

- **Bertoletti Matteo** — matr. 65865A
- **Invernizzi Carlo** — matr. 65885A

University of [your university name], academic year 2025/2026

---

## License

This is a university project, not licensed for redistribution.