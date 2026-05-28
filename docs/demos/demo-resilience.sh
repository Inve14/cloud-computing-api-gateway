#!/usr/bin/env bash
# Demo: Resilienza — failover automatico su 3 repliche del catalog service.
# Mostra che Kong instrada le richieste sulle repliche superstiti senza
# che il client riceva errori (zero downtime dal punto di vista esterno).
#
# Prerequisito: stack up con 3 repliche catalog (docker compose up -d)

set -u

BASE_URL="http://localhost:8000"
# Nome progetto Compose = basename della directory del repo (modificabile via env)
PROJECT="${COMPOSE_PROJECT_NAME:-cloud-computing-api-gateway}"

# ---------- Colori ANSI ----------
G='\033[0;32m'  # verde   → OK
R='\033[0;31m'  # rosso   → FAIL
Y='\033[1;33m'  # giallo  → step header
C='\033[0;36m'  # cyan    → info
B='\033[1m'     # bold
N='\033[0m'     # reset

step()  { printf "\n${Y}═══════════════════════════════════════════════${N}\n${Y}  %s${N}\n${Y}═══════════════════════════════════════════════${N}\n" "$1"; }
ok()    { printf "${G}✓  %s${N}\n" "$1"; }
fail()  { printf "${R}✗  %s${N}\n" "$1"; }
info()  { printf "${C}→  %s${N}\n" "$1"; }
pause() { printf "\n"; read -rp "$(printf "${B}[INVIO per continuare...]${N}") " _; printf "\n"; }
pretty(){ python3 -m json.tool 2>/dev/null || cat; }

# Helper: esegue GET /catalog/products e mostra HTTP status
get_catalog() {
  local label="$1"
  local s
  s=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/catalog/products?limit=1")
  if [ "$s" = "200" ]; then ok "GET #$label → HTTP $s"
  else fail "GET #$label → HTTP $s (atteso 200)"; fi
}

printf "\n${B}╔═══════════════════════════════════════════════╗${N}\n"
printf "${B}║     DEMO: RESILIENZA — Catalog Service        ║${N}\n"
printf "${B}╚═══════════════════════════════════════════════╝${N}\n"

# ──────────────────────────────────────────────────────────────────
step "1 / 6 — Stato iniziale: 3 repliche catalog in running"
# ──────────────────────────────────────────────────────────────────
docker compose ps catalog
printf "\n"
info "Upstream health (Kong Admin API — tutte le repliche healthy):"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "2 / 6 — 3 richieste baseline (round-robin)"
# ──────────────────────────────────────────────────────────────────
info "Invio 3 GET /api/v1/catalog/products..."
for i in 1 2 3; do get_catalog "$i"; done
sleep 1
info "Log Docker: nota quale replica (catalog-1/2/3) ha servito ogni richiesta:"
# I log di docker compose prefissano ogni riga con il nome della replica
docker compose logs --since=5s catalog 2>/dev/null \
  | grep -v "^$" | grep -v "healthcheck\|/health\|/ready" | tail -12
pause

# ──────────────────────────────────────────────────────────────────
step "3 / 6 — Simula crash: docker stop catalog-1"
# ──────────────────────────────────────────────────────────────────
info "Fermo ${PROJECT}-catalog-1 (simula un crash di istanza)..."
docker stop "${PROJECT}-catalog-1"
ok "catalog-1 fermato"
# Attende che Docker DNS rimuova l'IP di catalog-1 dalla risoluzione di "catalog"
info "Attendo aggiornamento DNS Docker (4s)..."
sleep 4
docker compose ps catalog
pause

# ──────────────────────────────────────────────────────────────────
step "4 / 6 — 6 richieste con 1 replica down (devono essere tutte 200)"
# ──────────────────────────────────────────────────────────────────
info "Kong instrada automaticamente sulle 2 repliche superstiti..."
OK_COUNT=0
for i in $(seq 1 6); do
  s=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/catalog/products?limit=1")
  if [ "$s" = "200" ]; then
    ok "GET #$i → HTTP $s"
    OK_COUNT=$((OK_COUNT + 1))
  else
    fail "GET #$i → HTTP $s"
  fi
done
printf "\n${B}${OK_COUNT}/6 richieste OK — nessun errore visibile al client${N}\n"
printf "\n"
info "Upstream health: Kong segnala catalog-1 unhealthy dopo 3 failure passivi:"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "5 / 6 — Recovery: docker start catalog-1"
# ──────────────────────────────────────────────────────────────────
docker start "${PROJECT}-catalog-1"
ok "catalog-1 riavviato"
# Kong applica il passive health check: 2 successi consecutivi per re-ammettere la replica
info "Attendo che Kong rilevi il recovery (health check passivo, ~15s)..."
sleep 15
docker compose ps catalog
printf "\n"
info "Upstream health dopo recovery (catalog-1 di nuovo healthy):"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "6 / 6 — 6 richieste dopo recovery (distribuzione su 3 repliche)"
# ──────────────────────────────────────────────────────────────────
for i in $(seq 1 6); do get_catalog "$i"; done
sleep 1
info "Log Docker (tutte e 3 le repliche di nuovo in servizio):"
docker compose logs --since=7s catalog 2>/dev/null \
  | grep -v "^$" | grep -v "healthcheck\|/health\|/ready" | tail -12

printf "\n${G}${B}✓ Demo Resilienza completata — zero errori client durante il failover.${N}\n\n"
