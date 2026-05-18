# Cloud Computing API Gateway

Mini e-commerce application built on a microservices architecture with an API Gateway as the single entry point.

**Course**: Cloud Computing and Technologies — University of Milan, A.Y. 2025/2026
**Authors**: Carlo Invernizzi (65885A), Matteo Bertoletti (65865A)

---

## Live deployment

| | |
|---|---|
| Base URL | `https://cloud-computing-uni.duckdns.org` |
| Example | `GET /api/v1/catalog/products` |
| Demo admin | `admin@example.com` / `Password123!` |
| Demo customer | `customer@example.com` / `Password123!` |

> The AWS EC2 instance may be stopped between sessions to stay within free-tier limits.

---

## Architecture

Traffic enters through nginx (TLS termination) and is forwarded to the Kong API Gateway, which handles routing, JWT validation, and rate limiting across replicated microservices.

```
Client (HTTPS 443)
       │
       ▼
 ┌───────────┐
 │   nginx   │  TLS termination, proxy_pass → 127.0.0.1:8000
 └─────┬─────┘
       │
       ▼
 ┌───────────┐
 │   Kong    │  JWT RS256, rate limiting, load balancing, passive health checks
 │  3.9.1    │
 └─────┬─────┘
       │
  ┌────┴──────────────────────┐
  │           │               │               │
  ▼           ▼               ▼               ▼
catalog×3   users×2        orders×2       payments×2
  │           │               │               │
  ▼           ▼               ▼               ▼
catalog-db  users-db       orders-db      payments-db
(master +   (single)       (single)        (single)
 replica)

                    Prometheus ←── scrapes all 5 services
                    Grafana    ←── queries Prometheus
```

---

## Tech stack

- **Runtime**: Node.js 20 LTS
- **Web framework**: Fastify 4.28.1 (JSON Schema validation built-in)
- **Database**: PostgreSQL 16.3
- **ORM**: Prisma (catalog, users) / raw pg driver (orders, payments)
- **API Gateway**: Kong 3.9.1 community, DB-less declarative mode
- **Metrics**: prom-client 15.1.3, Prometheus 2.51.2, Grafana 10.4.2
- **Auth**: JWT RS256 via `@fastify/jwt` 8.0.1; bcrypt cost-factor 12
- **HTTPS**: nginx + Let's Encrypt (certbot), DuckDNS for DNS
- **Containers**: Docker Compose

---

## The four demos

### ✅ Resilience
Kill one catalog replica while k6 generates load; Kong's passive health checks reroute traffic to the remaining two replicas within seconds. Zero downtime on the catalog endpoints.

```bash
# Kill one replica
docker compose stop $(docker ps --filter name=catalog --format "{{.Names}}" | head -1)
# Watch k6 keep running
k6 run scripts/load-tests/catalog.js
```

### ✅ Security
JWT RS256: the `users` service holds the private key; Kong holds only the public key and validates every token at the gateway before the request reaches any microservice. Login is rate-limited to 10 req/min per IP; browsing to 100 req/min. Passwords are bcrypt-hashed at cost 12. All inter-service traffic stays on the internal Docker network; only Kong is reachable from outside.

```bash
# Get a token
curl -X POST https://cloud-computing-uni.duckdns.org/api/v1/users/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"customer@example.com","password":"Password123!"}'

# Trigger rate-limit (10 rapid login attempts)
for i in $(seq 1 12); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST https://cloud-computing-uni.duckdns.org/api/v1/users/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"x@x.com","password":"wrong"}'; done
```

### ✅ Replication
The catalog database runs as a PostgreSQL streaming replication pair (master + hot standby). The catalog service reads from the replica and writes to the master. Kill the master; the replica promotes and reads continue. Microservice replicas are declared via `deploy.replicas` in `docker-compose.yml`.

```bash
# Simulate master failure
bash scripts/chaos/kill-catalog-db-master.sh
```

### ✅ Cloud deployment
AWS EC2 Ubuntu 22.04, single VM, all services containerised. HTTPS via Let's Encrypt + DuckDNS. Provisioned with a single setup script; reproducible from scratch.

```bash
# Provision HTTPS on a fresh VM
sudo bash deployment/aws/setup-https.sh
```

---

## Quick start (local)

**Prerequisites**: Docker Desktop, `git`.

```bash
git clone <repo-url>
cd cloud-computing-api-gateway
cp .env.example .env         # fill in the passwords
docker compose up -d
```

| URL | Service |
|-----|---------|
| `http://localhost:8000` | Kong proxy (all API routes) |
| `http://localhost:8001` | Kong Admin API (dev only — never expose in prod) |
| `http://localhost:3000` | Grafana (anonymous viewer, admin/admin) |
| `http://localhost:9090` | Prometheus |

Scale a service:
```bash
docker compose up -d --scale catalog=3
```

Tail logs:
```bash
docker compose logs -f orders
```

Stop everything (keep volumes):
```bash
docker compose down
```

---

## Cloud deployment (AWS EC2)

```bash
# 1. SSH into the VM
ssh -i ~/.ssh/key.pem ubuntu@16.171.60.33

# 2. Clone the repo
git clone <repo-url> /opt/app && cd /opt/app
cp .env.example .env   # fill secrets

# 3. Set up HTTPS (nginx + certbot, idempotent)
sudo bash deployment/aws/setup-https.sh

# 4. Start the stack
docker compose up -d
```

Requires AWS Security Group inbound rules: **22** (SSH, restricted IPs), **80** (HTTP), **443** (HTTPS). All other ports closed.

---

## Documentation

- `docs/api-contracts/` — OpenAPI specs per service (catalog, users, orders, payments)
- `docs/architecture/` — Database schemas, architecture decision records
- `infrastructure/kong/kong.yml` — Full Gateway routing and plugin configuration
- `infrastructure/monitoring/` — Prometheus scrape config, alert rules, Grafana dashboard

---

## Known limitations

- **Kong runs as a single container** (`container_name` prevents `docker compose scale`; adding a second Kong instance requires a load balancer in front of it, which is out of scope for this project).
- **No automated CI/CD pipeline** — deployment is manual via SSH.
- **AWS instance is stopped between sessions** to avoid consuming free-tier credits; cold start takes ~60 seconds.
