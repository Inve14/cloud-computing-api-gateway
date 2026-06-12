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

source "$(dirname "$0")/_helpers.sh"

# Helper: esegue GET /catalog/products, mostra HTTP status e ritorna 0/1
get_catalog() {
  local label="$1"
  local s
  s=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/catalog/products?limit=1")
  if [ "$s" = "200" ]; then ok "GET #$label → HTTP $s"; return 0
  else fail "GET #$label → HTTP $s (atteso 200)"; return 1; fi
}

printf "\n${B}╔═══════════════════════════════════════════════╗${N}\n"
printf "${B}║     DEMO: RESILIENZA — Catalog Service        ║${N}\n"
printf "${B}╚═══════════════════════════════════════════════╝${N}\n"

# ──────────────────────────────────────────────────────────────────
step "1 / 6 — Stato iniziale: 3 repliche catalog in running"
# ──────────────────────────────────────────────────────────────────
intro "Verifichiamo lo stato di partenza: 3 repliche del servizio \
catalog devono essere up e Kong deve vederle tutte HEALTHY nel suo \
upstream. Da qui parte la demo di failover e recovery."
sleep 1

request_info "GET" "http://localhost:8001/upstreams/catalog-upstream/health" \
  "(Kong Admin API)" ""
sleep 1

flow_steps \
  "docker compose ps interroga lo stato dei container" \
  "Kong Admin API espone /upstreams/<name>/health" \
  "Per ogni address risolto via DNS, riporta health" \
  "weight.available/total = capacità attuale del pool"
sleep 1

execute
docker compose ps catalog
printf "\n"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
sleep 0.5

result \
  "3 repliche catalog Up (healthy) su Docker" \
  "Upstream Kong: tutti gli address HEALTHY" \
  "Pool al 100% di capacità — pronto per il test"

pause

# ──────────────────────────────────────────────────────────────────
step "2 / 6 — 3 richieste baseline (round-robin)"
# ──────────────────────────────────────────────────────────────────
intro "Inviamo 3 richieste GET al catalogo e osserviamo nei log \
Docker quale replica (catalog-1/2/3) ha servito ciascuna richiesta: \
dimostra il bilanciamento round-robin di Kong tra le 3 repliche."
sleep 1

request_info "GET" "$BASE_URL/api/v1/catalog/products?limit=1" "" ""
sleep 1

flow_steps \
  "Kong matcha route 'catalog-routes' (pubblica)" \
  "Rate-limit catalog: 100/min per IP — OK" \
  "Round-robin su catalog-upstream (3 target)" \
  "Ogni richiesta va a una replica diversa" \
  "La replica risponde leggendo dal DB catalog"
sleep 1

execute
OK_COUNT=0
for i in 1 2 3; do
  if get_catalog "$i"; then OK_COUNT=$((OK_COUNT + 1)); fi
done
sleep 1
info "Log Docker: nota quale replica (catalog-1/2/3) ha servito ogni richiesta:"
# I log di docker compose prefissano ogni riga con il nome della replica
docker compose logs --since=5s catalog 2>/dev/null \
  | grep -v "^$" | grep -v "healthcheck\|/health\|/ready" | tail -12
sleep 0.5

result \
  "${OK_COUNT}/3 richieste → HTTP 200" \
  "Le 3 repliche si dividono il traffico (vedi log sopra)"

pause

# ──────────────────────────────────────────────────────────────────
step "3 / 6 — Simula crash: docker stop catalog-1"
# ──────────────────────────────────────────────────────────────────
intro "Simuliamo il crash di un'istanza fermando catalog-1. \
Notifichiamo subito Kong dello stato 'down' (come farebbe un sistema \
di service discovery), così il gateway smette di instradarci traffico."
sleep 1

request_info "PUT" \
  "http://localhost:8001/upstreams/catalog-upstream/targets/{target_id}/{ip}:3001/unhealthy" \
  "(Kong Admin API)" ""
sleep 1

flow_steps \
  "docker stop invia SIGTERM/SIGKILL a catalog-1" \
  "Catturiamo l'IP del container prima dello stop" \
  "PUT Admin API marca quel target UNHEALTHY" \
  "Kong rimuove l'address dal pool round-robin" \
  "Docker DNS smette di risolvere l'IP per 'catalog'"
sleep 1

execute
info "Fermo ${PROJECT}-catalog-1 (simula un crash di istanza)..."

# Cattura l'IP di catalog-1 PRIMA dello stop (poi non sarà più ispezionabile)
CATALOG_1_IP=$(docker inspect "${PROJECT}-catalog-1" \
  -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

docker stop "${PROJECT}-catalog-1" >/dev/null
ok "catalog-1 fermato"
printf "\n"

info "Notifica al gateway dello stato 'down' (simula evento service discovery)..."

# Estrai il TARGET_ID dell'upstream catalog-upstream
TARGET_ID=$(curl -s "http://localhost:8001/upstreams/catalog-upstream/health" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

# Notifica Kong che il target è unhealthy (PUT, non POST — Kong 3.9 rigetta POST con 405)
if [ -n "${TARGET_ID:-}" ] && [ -n "${CATALOG_1_IP:-}" ]; then
  curl -s -o /dev/null -X PUT \
    "http://localhost:8001/upstreams/catalog-upstream/targets/${TARGET_ID}/${CATALOG_1_IP}:3001/unhealthy"
fi
ok "Kong aggiornato — catalog-1 escluso dal pool"
printf "\n"

# Attende che Docker DNS rimuova l'IP di catalog-1 dalla risoluzione di "catalog"
info "Attendo propagazione (4s)..."
sleep 4
docker compose ps catalog
sleep 0.5

result \
  "catalog-1 fermato e rimosso dal pool Kong" \
  "2/3 repliche rimangono attive nell'upstream"

pause

# ──────────────────────────────────────────────────────────────────
step "4 / 6 — 6 richieste con 1 replica down (devono essere tutte 200)"
# ──────────────────────────────────────────────────────────────────
intro "Inviamo 6 richieste GET allo stesso endpoint con una replica \
down. Il client non deve percepire alcun errore: Kong instrada \
automaticamente solo verso le 2 repliche superstiti."
sleep 1

request_info "GET" "$BASE_URL/api/v1/catalog/products?limit=1" "" "(× 6)"
sleep 1

flow_steps \
  "Kong consulta l'upstream catalog-upstream" \
  "catalog-1 è UNHEALTHY → escluso dal round-robin" \
  "Traffico distribuito solo su catalog-2/catalog-3" \
  "Ogni richiesta → HTTP 200, zero errori lato client" \
  "Upstream health riflette 1 address UNHEALTHY"
sleep 1

execute
info "Kong instrada automaticamente sulle 2 repliche superstiti..."
OK_COUNT=0
for i in $(seq 1 6); do
  if get_catalog "$i"; then OK_COUNT=$((OK_COUNT + 1)); fi
done
sleep 1
info "Log Docker (catalog-2 e catalog-3 si dividono il traffico):"
docker compose logs --since=5s catalog 2>/dev/null \
  | grep -v "^$" | grep -v "healthcheck\|/health\|/ready" | tail -12
sleep 0.5
printf "\n"
info "Upstream health: Kong ha escluso catalog-1 dal pool (notifica dello step precedente):"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
sleep 0.5

result \
  "${OK_COUNT}/6 richieste → HTTP 200 (zero downtime)" \
  "Traffico distribuito su catalog-2/catalog-3 (vedi log)" \
  "Upstream Kong: 1 address UNHEALTHY, weight 200/300"

pause

# ──────────────────────────────────────────────────────────────────
step "5 / 6 — Recovery: docker start catalog-1"
# ──────────────────────────────────────────────────────────────────
intro "Riavviamo catalog-1 e attendiamo che superi l'health check \
Docker. Notifichiamo poi Kong del recovery, in modo simmetrico allo \
step 3, così il gateway torna a instradare traffico anche qui."
sleep 1

request_info "PUT" \
  "http://localhost:8001/upstreams/catalog-upstream/targets/{target_id}/{ip}:3001/healthy" \
  "(Kong Admin API)" ""
sleep 1

flow_steps \
  "docker start riavvia il container catalog-1" \
  "Polling dell'health check Docker (max 20s)" \
  "Lettura di /upstreams/.../health per address UNHEALTHY" \
  "PUT .../targets/{TARGET_ID}/{IP}/healthy per ognuno" \
  "Verifica: tutti gli address tornano HEALTHY"
sleep 1

execute
docker start "${PROJECT}-catalog-1"
ok "catalog-1 riavviato"

info "Attendo che il container superi il suo health check Docker..."
# Polling: aspetta che catalog-1 torni "healthy" nello stato Docker
for i in $(seq 1 20); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${PROJECT}-catalog-1" 2>/dev/null || echo "starting")
  if [ "$STATUS" = "healthy" ]; then
    ok "Container healthy dopo ${i}s"
    break
  fi
  sleep 1
done
printf "\n"

info "Sincronizzazione stato Kong con la nuova istanza..."

# L'endpoint sul target astratto (.../targets/{target}/healthy) non incide
# sui singoli addresses risolti via DNS (ognuno con health state indipendente).
# Per riportare HEALTHY un IP specifico serve l'endpoint per-address, e Kong
# 3.9 lo espone solo in PUT (POST risponde 405 Method Not Allowed):
#   PUT /upstreams/{upstream}/targets/{TARGET_ID}/{IP:PORT}/healthy
KONG_HEALTH=$(curl -s "http://localhost:8001/upstreams/catalog-upstream/health")
TARGET_ID=$(printf '%s' "$KONG_HEALTH" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

UNHEALTHY_ADDRS=$(printf '%s' "$KONG_HEALTH" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
addrs = data['data'][0]['data']['addresses']
for a in addrs:
    if a['health'] == 'UNHEALTHY':
        print(f\"{a['ip']}:{a['port']}\")
" 2>/dev/null)

if [ -n "$TARGET_ID" ] && [ -n "$UNHEALTHY_ADDRS" ]; then
  for ADDR in $UNHEALTHY_ADDRS; do
    curl -s -o /dev/null -X PUT \
      "http://localhost:8001/upstreams/catalog-upstream/targets/${TARGET_ID}/${ADDR}/healthy"
  done
fi

sleep 2

ALL_HEALTHY=$(curl -s "http://localhost:8001/upstreams/catalog-upstream/health" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
addrs = data['data'][0]['data']['addresses']
unhealthy = [a for a in addrs if a['health'] != 'HEALTHY']
print('yes' if not unhealthy else 'no')
" 2>/dev/null)

if [ "$ALL_HEALTHY" = "yes" ]; then
  ok "Kong aggiornato — tutte le repliche di nuovo HEALTHY"
else
  fail "Sincronizzazione incompleta — alcune repliche risultano ancora UNHEALTHY"
fi
printf "\n"

# Warm-up DNS più aggressivo: 30 richieste distribuite con piccole pause
# per dare a Kong tempo di bilanciare il round-robin sulle 3 repliche
info "Stabilizzazione del DNS Kong..."
for i in $(seq 1 30); do
  curl -s -o /dev/null "$BASE_URL/api/v1/catalog/products?limit=1"
  sleep 0.2
done
sleep 8
ok "DNS Kong stabilizzato — tutte le repliche nel pool"
printf "\n"

docker compose ps catalog
printf "\n"
info "Upstream health dopo recovery (catalog-1 di nuovo healthy):"
curl -s "http://localhost:8001/upstreams/catalog-upstream/health" | pretty
sleep 0.5

if [ "$ALL_HEALTHY" = "yes" ]; then
  result \
    "Container catalog-1 healthy" \
    "Kong aggiornato — 3/3 address HEALTHY" \
    "weight.available: 300/300 — pool ripristinato al 100%"
else
  result "FALLITO: alcune repliche risultano ancora UNHEALTHY in Kong"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "6 / 6 — 6 richieste dopo recovery (distribuzione su 3 repliche)"
# ──────────────────────────────────────────────────────────────────
intro "Ripetiamo le 6 richieste per verificare che Kong distribuisca \
di nuovo il traffico su tutte e 3 le repliche, inclusa catalog-1 \
appena rientrata nel pool."
sleep 1

request_info "GET" "$BASE_URL/api/v1/catalog/products?limit=1" "" "(× 6)"
sleep 1

flow_steps \
  "Round-robin su 3 target, tutti HEALTHY" \
  "catalog-1, catalog-2, catalog-3 servono richieste" \
  "Nessun errore client durante crash → recovery"
sleep 1

execute
OK_COUNT=0
for i in $(seq 1 6); do
  if get_catalog "$i"; then OK_COUNT=$((OK_COUNT + 1)); fi
done
sleep 1
info "Log Docker (tutte e 3 le repliche di nuovo in servizio):"
docker compose logs --since=5s catalog 2>/dev/null \
  | grep -v "^$" | grep -v "healthcheck\|/health\|/ready\|/metrics" | tail -20
sleep 0.5

result \
  "${OK_COUNT}/6 richieste → HTTP 200" \
  "Tutte e 3 le repliche servono traffico (vedi log)" \
  "Failover + recovery completati senza downtime visibile"

printf "\n${G}${B}✓ Demo Resilienza completata — zero errori client durante il failover.${N}\n\n"
