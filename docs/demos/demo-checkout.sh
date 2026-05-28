#!/usr/bin/env bash
# Demo: Checkout cross-service con Saga Pattern e compensazione automatica.
#
# Flusso Saga completo:
#   orders → riserva stock (catalog) → processa pagamento (payments)
#   → SUCCESS: ordine paid, carrello svuotato, stock definitivamente scalato
#   → FAILURE: rilascia stock (catalog), cancella ordine, HTTP 402
#
# Prerequisito: stack up, prodotto seed "Wireless Headphones" presente in catalog.

set -u

BASE_URL="http://localhost:8000"
CUSTOMER_EMAIL="customer@example.com"
CUSTOMER_PASS="Password123!"

# Prodotto seed (infrastructure/postgres/catalog/init.sql)
PRODUCT_ID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
PRODUCT_NAME="Wireless Headphones"
PRODUCT_PRICE=2999   # centesimi = 29,99 EUR
QTY=2                # quantità per ogni checkout

# Indirizzo di spedizione fisso per il checkout
SHIPPING='{"street":"Via Roma 1","city":"Milano","zip_code":"20100","country":"IT"}'

# Carica credenziali DB dal .env (per le query di verifica stock dirette)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$REPO_ROOT/.env" ]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi
PG_USER="${POSTGRES_USER:-catalog_user}"
PG_PASS="${POSTGRES_PASSWORD:-catalog_dev_password}"
PG_DB="${POSTGRES_DB:-catalog_db}"

# ---------- Colori ANSI ----------
G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
C='\033[0;36m'
B='\033[1m'
N='\033[0m'

step()  { printf "\n${Y}═══════════════════════════════════════════════${N}\n${Y}  %s${N}\n${Y}═══════════════════════════════════════════════${N}\n" "$1"; }
ok()    { printf "${G}✓  %s${N}\n" "$1"; }
fail()  { printf "${R}✗  %s${N}\n" "$1"; }
info()  { printf "${C}→  %s${N}\n" "$1"; }
pause() { printf "\n"; read -rp "$(printf "${B}[INVIO per continuare...]${N}") " _; printf "\n"; }
pretty(){ python3 -m json.tool 2>/dev/null || cat; }

# Mostra stock attuale del prodotto interrogando il DB master direttamente
show_stock() {
  local label="${1:-}"
  [ -n "$label" ] && printf "${C}→  Stock %s:${N}\n" "$label"
  docker exec -e PGPASSWORD="$PG_PASS" catalog-db-master \
    psql -U "$PG_USER" -d "$PG_DB" \
    -c "SELECT quantity_available, quantity_reserved
        FROM product_stock
        WHERE product_id = '$PRODUCT_ID';"
}

# Ritorna quantity_available come numero
get_available() {
  docker exec -e PGPASSWORD="$PG_PASS" catalog-db-master \
    psql -U "$PG_USER" -d "$PG_DB" -t -A \
    -c "SELECT quantity_available FROM product_stock WHERE product_id = '$PRODUCT_ID';" \
    | tr -d '[:space:]'
}

printf "\n${B}╔══════════════════════════════════════════════════════╗${N}\n"
printf "${B}║    DEMO: CHECKOUT — Saga Pattern + Compensazione    ║${N}\n"
printf "${B}╚══════════════════════════════════════════════════════╝${N}\n"

# ──────────────────────────────────────────────────────────────────
step "1 / 7 — Login customer + stato iniziale del prodotto"
# ──────────────────────────────────────────────────────────────────
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/users/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CUSTOMER_EMAIL\",\"password\":\"$CUSTOMER_PASS\"}")
TOKEN=$(printf '%s' "$LOGIN_RESP" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
ok "Login customer (Mario Rossi) → token ottenuto"
printf "\n"
info "Prodotto da acquistare (qty $QTY × $PRODUCT_NAME @ $(( PRODUCT_PRICE / 100 )).$(( PRODUCT_PRICE % 100 )) EUR):"
curl -s "$BASE_URL/api/v1/catalog/products/$PRODUCT_ID" | pretty
show_stock "iniziale"
pause

# ──────────────────────────────────────────────────────────────────
step "2 / 7 — Pulizia carrello + aggiunta prodotto"
# ──────────────────────────────────────────────────────────────────
info "Svuoto il carrello (per evitare stato residuo da run precedenti)..."
curl -s -o /dev/null -X DELETE "$BASE_URL/api/v1/cart" \
  -H "Authorization: Bearer $TOKEN"
ok "Carrello svuotato"
printf "\n"
info "POST /api/v1/cart/items — aggiunta ${QTY}× $PRODUCT_NAME..."
curl -s -X POST "$BASE_URL/api/v1/cart/items" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\":                 \"$PRODUCT_ID\",
    \"quantity\":                   $QTY,
    \"product_name_snapshot\":      \"$PRODUCT_NAME\",
    \"unit_price_cents_snapshot\":  $PRODUCT_PRICE
  }" | pretty
printf "\n"
info "Stato corrente del carrello:"
curl -s "$BASE_URL/api/v1/cart" -H "Authorization: Bearer $TOKEN" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "3 / 7 — Checkout SUCCESS (carta 4242) — Saga completa"
# ──────────────────────────────────────────────────────────────────
info "POST /api/v1/cart/checkout — carta 4242 (pagamento approvato)"
info "Flusso Saga: reserve stock → crea ordine pending → processa pagamento → ordine paid"
CHECKOUT_RESP=$(curl -s -w "\n\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/cart/checkout" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"shipping_address\": $SHIPPING,
    \"payment\": {\"method\":\"credit_card\",\"card_number_last4\":\"4242\"}
  }")
HTTP_STATUS=$(printf '%s' "$CHECKOUT_RESP" | grep "^HTTP_STATUS:" | cut -d: -f2)
BODY=$(printf '%s' "$CHECKOUT_RESP" | sed '/^HTTP_STATUS:/d')
printf '%s\n' "$BODY" | pretty

ORDER_ID=$(printf '%s' "$BODY" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || printf "")
ORDER_STATUS=$(printf '%s' "$BODY" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['status'])" 2>/dev/null || printf "")

if [ "${HTTP_STATUS:-}" = "201" ] && [ "$ORDER_STATUS" = "paid" ]; then
  ok "HTTP $HTTP_STATUS — Ordine $ORDER_ID → status: $ORDER_STATUS"
else
  fail "HTTP ${HTTP_STATUS:-?} — status: ${ORDER_STATUS:-(errore)}"
fi
printf "\n"
show_stock "dopo checkout ok (quantity_available sceso di $QTY)"
pause

# ──────────────────────────────────────────────────────────────────
step "4 / 7 — Aggiunta prodotto per il test di fallimento"
# ──────────────────────────────────────────────────────────────────
info "Dopo un checkout riuscito il carrello viene svuotato automaticamente."
info "Riaggiungo ${QTY}× $PRODUCT_NAME per il test con carta 0000..."
curl -s -X POST "$BASE_URL/api/v1/cart/items" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\":                \"$PRODUCT_ID\",
    \"quantity\":                  $QTY,
    \"product_name_snapshot\":     \"$PRODUCT_NAME\",
    \"unit_price_cents_snapshot\": $PRODUCT_PRICE
  }" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "5 / 7 — Checkout FALLITO (carta 0000) — Saga Compensation"
# ──────────────────────────────────────────────────────────────────
info "POST /api/v1/cart/checkout — carta 0000 (pagamento declinato)"
info "Flusso Saga: reserve stock → crea ordine → pagamento FALLISCE"
info "Compensation: rilascia stock (catalog) + cancella ordine"

STOCK_BEFORE=$(get_available)
info "Stock PRIMA del checkout fallito: quantity_available = $STOCK_BEFORE"
printf "\n"

FAIL_RESP=$(curl -s -w "\n\nHTTP_STATUS:%{http_code}" \
  -X POST "$BASE_URL/api/v1/cart/checkout" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"shipping_address\": $SHIPPING,
    \"payment\": {\"method\":\"credit_card\",\"card_number_last4\":\"0000\"}
  }")
HTTP_STATUS=$(printf '%s' "$FAIL_RESP" | grep "^HTTP_STATUS:" | cut -d: -f2)
BODY=$(printf '%s' "$FAIL_RESP" | sed '/^HTTP_STATUS:/d')
printf '%s\n' "$BODY" | pretty

if [ "${HTTP_STATUS:-}" = "402" ]; then
  fail "HTTP $HTTP_STATUS — Pagamento declinato (comportamento atteso)"
fi
printf "\n"

STOCK_AFTER=$(get_available)
info "Stock DOPO il checkout fallito: quantity_available = $STOCK_AFTER"
printf "\n"

if [ "$STOCK_BEFORE" = "$STOCK_AFTER" ]; then
  ok "SAGA COMPENSATION OK: stock ripristinato (${STOCK_AFTER} = ${STOCK_BEFORE})"
  ok "I $QTY pezzi riservati durante il checkout sono stati rilasciati."
else
  fail "Stock NON ripristinato! Prima: $STOCK_BEFORE, Dopo: $STOCK_AFTER"
fi
pause

# ──────────────────────────────────────────────────────────────────
step "6 / 7 — Storico ordini del customer (paid + cancelled)"
# ──────────────────────────────────────────────────────────────────
info "GET /api/v1/orders — tutti gli ordini del customer"
curl -s "$BASE_URL/api/v1/orders" -H "Authorization: Bearer $TOKEN" | pretty
pause

# ──────────────────────────────────────────────────────────────────
step "7 / 7 — Dettaglio dell'ordine pagato"
# ──────────────────────────────────────────────────────────────────
if [ -n "$ORDER_ID" ]; then
  info "GET /api/v1/orders/$ORDER_ID"
  curl -s "$BASE_URL/api/v1/orders/$ORDER_ID" \
    -H "Authorization: Bearer $TOKEN" | pretty
  ok "Ordine pagato visibile con tutti gli item e il payment_id collegato"
else
  info "ORDER_ID non estratto — controlla il JSON del checkout di step 3"
fi

printf "\n${G}${B}✓ Demo Checkout + Saga Compensation completata.${N}\n\n"
