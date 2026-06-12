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

source "$(dirname "$0")/_helpers.sh"

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
intro "Effettuiamo il login del cliente Mario Rossi e controlliamo lo \
stato iniziale del prodotto che acquisteremo: prezzo a catalogo e \
stock disponibile/riservato nel database."
sleep 1

request_info "POST" "$BASE_URL/api/v1/users/auth/login" \
  "Content-Type: application/json" \
  "{\"email\":\"$CUSTOMER_EMAIL\",\"password\":\"***\"}"
sleep 1

flow_steps \
  "Kong matcha route 'users-auth-login' (rate limit 10/min)" \
  "users-service: bcrypt.compare → JWT RS256" \
  "GET /api/v1/catalog/products/{id} (route pubblica)" \
  "catalog-service legge prodotto + stock dal DB" \
  "Query diretta a catalog-db-master per lo stock"
sleep 1

execute
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/users/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CUSTOMER_EMAIL\",\"password\":\"$CUSTOMER_PASS\"}")

# Estrazione token robusta: usa .get() invece di [], niente eccezione
TOKEN=$(printf '%s' "$LOGIN_RESP" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

# Verifica esplicita: se token vuoto, mostra risposta server e termina
if [ -z "$TOKEN" ]; then
  fail "Login fallito — token non ricevuto dal server."
  printf "\n${C}→  Risposta del server:${N}\n"
  printf '%s\n' "$LOGIN_RESP" | pretty
  printf "\n${Y}Possibili cause:${N}\n"
  printf "  • Rate limit Kong attivo (10/min per IP su /auth/login)\n"
  printf "    → Attendi 60 secondi e rilancia.\n"
  printf "  • Credenziali errate (verifica seed: customer@example.com / Password123!)\n"
  printf "  • Stack non avviato o users service unhealthy\n"
  printf "    → docker compose ps\n\n"
  exit 1
fi

info "Prodotto da acquistare (qty $QTY × $PRODUCT_NAME @ $(( PRODUCT_PRICE / 100 )).$(( PRODUCT_PRICE % 100 )) EUR):"
curl -s "$BASE_URL/api/v1/catalog/products/$PRODUCT_ID" | pretty
show_stock "iniziale"
sleep 0.5

result \
  "Login OK — token JWT RS256 ottenuto" \
  "Prodotto e stock iniziale recuperati"

pause

# ──────────────────────────────────────────────────────────────────
step "2 / 7 — Pulizia carrello + aggiunta prodotto"
# ──────────────────────────────────────────────────────────────────
intro "Puliamo il carrello da eventuali run precedenti (idempotenza) \
e aggiungiamo il prodotto scelto, popolando lo snapshot di nome e \
prezzo che orders userà per calcolare il totale dell'ordine."
sleep 1

request_info "POST" "$BASE_URL/api/v1/cart/items" \
  "Authorization: Bearer <token>, Content-Type: application/json" \
  "{\"product_id\":\"$PRODUCT_ID\",\"quantity\":$QTY,\"product_name_snapshot\":\"$PRODUCT_NAME\",\"unit_price_cents_snapshot\":$PRODUCT_PRICE}"
sleep 1

flow_steps \
  "DELETE /api/v1/cart svuota eventuali item residui" \
  "Kong valida JWT (route 'cart-routes')" \
  "orders-service: cartService.addItem()" \
  "Cart e item vivono nello stesso DB di orders" \
  "Snapshot di nome/prezzo salvato nell'item" \
  "GET /api/v1/cart restituisce lo stato aggiornato"
sleep 1

execute
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
sleep 0.5

result \
  "Carrello svuotato e ripopolato (idempotente)" \
  "${QTY}× $PRODUCT_NAME nel carrello, snapshot salvato"

pause

# ──────────────────────────────────────────────────────────────────
step "3 / 7 — Checkout SUCCESS (carta 4242) — Saga completa"
# ──────────────────────────────────────────────────────────────────
intro "Eseguiamo il checkout con una carta che simula un pagamento \
approvato. Si attiva l'intera Saga: riserva dello stock su catalog, \
creazione dell'ordine, pagamento e finalizzazione a 'paid'."
sleep 1

request_info "POST" "$BASE_URL/api/v1/cart/checkout" \
  "Authorization: Bearer <token>, Content-Type: application/json" \
  "{\"shipping_address\":{...},\"payment\":{\"method\":\"credit_card\",\"card_number_last4\":\"4242\"}}"
sleep 1

flow_steps \
  "Kong valida JWT (route 'cart-routes')" \
  "Per ogni item: POST catalog /stock/reserve" \
  "catalog: available -= qty, reserved += qty" \
  "orders crea ordine status='pending' (transazione SQL)" \
  "orders → payments: processPayment() (4242 → completed)" \
  "orders aggiorna ordine a status='paid' + payment_id" \
  "Carrello svuotato automaticamente"
sleep 1

execute
info "POST /api/v1/cart/checkout — carta 4242 (pagamento approvato)"
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
printf "\n"
show_stock "dopo checkout ok (quantity_available sceso di $QTY)"
sleep 0.5

if [ "${HTTP_STATUS:-}" = "201" ] && [ "$ORDER_STATUS" = "paid" ]; then
  result \
    "HTTP $HTTP_STATUS — Ordine $ORDER_ID → status: $ORDER_STATUS" \
    "Stock decrementato di $QTY (vedi query sopra)" \
    "Saga completata: reserve → pending → paid"
else
  result "FALLITO: HTTP ${HTTP_STATUS:-?} — status: ${ORDER_STATUS:-(errore)}"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "4 / 7 — Aggiunta prodotto per il test di fallimento"
# ──────────────────────────────────────────────────────────────────
intro "Dopo un checkout riuscito il carrello è stato svuotato \
automaticamente. Ripopoliamo il carrello con la stessa quantità per \
preparare il test di pagamento fallito (Saga compensation)."
sleep 1

request_info "POST" "$BASE_URL/api/v1/cart/items" \
  "Authorization: Bearer <token>, Content-Type: application/json" \
  "{\"product_id\":\"$PRODUCT_ID\",\"quantity\":$QTY,\"product_name_snapshot\":\"$PRODUCT_NAME\",\"unit_price_cents_snapshot\":$PRODUCT_PRICE}"
sleep 1

flow_steps \
  "Kong valida JWT (route 'cart-routes')" \
  "orders-service: cartService.addItem() — nuovo item" \
  "Stesso prodotto/quantità del checkout precedente" \
  "Lo stock è già decrementato dallo step 3"
sleep 1

execute
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
sleep 0.5

result \
  "${QTY}× $PRODUCT_NAME ri-aggiunti al carrello" \
  "Pronto per il test di pagamento declinato (carta 0000)"

pause

# ──────────────────────────────────────────────────────────────────
step "5 / 7 — Checkout FALLITO (carta 0000) — Saga Compensation"
# ──────────────────────────────────────────────────────────────────
intro "Eseguiamo il checkout con una carta che simula un pagamento \
rifiutato (HTTP 402). Vogliamo dimostrare la compensazione della \
Saga: lo stock riservato viene rilasciato e l'ordine annullato."
sleep 1

request_info "POST" "$BASE_URL/api/v1/cart/checkout" \
  "Authorization: Bearer <token>, Content-Type: application/json" \
  "{\"shipping_address\":{...},\"payment\":{\"method\":\"credit_card\",\"card_number_last4\":\"0000\"}}"
sleep 1

flow_steps \
  "orders: reserve stock su catalog (come step 3)" \
  "orders crea ordine status='pending'" \
  "orders → payments: processPayment() (0000 → failed)" \
  "payments risponde status='failed'" \
  "Compensation: releaseStock() per ogni item" \
  "orders aggiorna ordine a status='cancelled'" \
  "Risposta HTTP 402 PAYMENT_FAILED"
sleep 1

execute
info "POST /api/v1/cart/checkout — carta 0000 (pagamento declinato)"

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
printf "\n"

STOCK_AFTER=$(get_available)
info "Stock DOPO il checkout fallito: quantity_available = $STOCK_AFTER"
sleep 0.5

if [ "${HTTP_STATUS:-}" = "402" ] && [ "$STOCK_BEFORE" = "$STOCK_AFTER" ]; then
  result \
    "HTTP $HTTP_STATUS — Pagamento declinato (comportamento atteso)" \
    "SAGA COMPENSATION OK: stock ripristinato (${STOCK_AFTER} = ${STOCK_BEFORE})" \
    "I $QTY pezzi riservati durante il checkout sono stati rilasciati"
elif [ "$STOCK_BEFORE" != "$STOCK_AFTER" ]; then
  result "FALLITO: stock NON ripristinato! Prima: $STOCK_BEFORE, Dopo: $STOCK_AFTER"
else
  result "FALLITO: HTTP ${HTTP_STATUS:-?} (atteso 402)"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "6 / 7 — Storico ordini del customer (paid + cancelled)"
# ──────────────────────────────────────────────────────────────────
intro "Recuperiamo lo storico ordini del cliente per verificare che \
siano visibili sia l'ordine pagato (step 3) sia quello annullato \
dalla compensazione (step 5)."
sleep 1

request_info "GET" "$BASE_URL/api/v1/orders" \
  "Authorization: Bearer <token>" ""
sleep 1

flow_steps \
  "Kong valida JWT (route 'orders-routes')" \
  "orders-service: listOrders(userId) — solo ordini propri" \
  "Risposta paginata, ordinata per created_at DESC"
sleep 1

execute
info "GET /api/v1/orders — tutti gli ordini del customer"
curl -s "$BASE_URL/api/v1/orders" -H "Authorization: Bearer $TOKEN" | pretty
sleep 0.5

result \
  "Storico ordini recuperato" \
  "Visibili gli ordini con status 'paid' e 'cancelled'"

pause

# ──────────────────────────────────────────────────────────────────
step "7 / 7 — Dettaglio dell'ordine pagato"
# ──────────────────────────────────────────────────────────────────
intro "Visualizziamo il dettaglio completo dell'ordine pagato allo \
step 3, con tutti gli item, i prezzi snapshot e il riferimento al \
pagamento elaborato da payments."
sleep 1

request_info "GET" "$BASE_URL/api/v1/orders/{order_id}" \
  "Authorization: Bearer <token>" ""
sleep 1

flow_steps \
  "Kong valida JWT (route 'orders-routes')" \
  "orders-service: getOrder() verifica ownership" \
  "Join con order_items per il dettaglio righe" \
  "payment_id collega l'ordine al pagamento"
sleep 1

execute
if [ -n "$ORDER_ID" ]; then
  info "GET /api/v1/orders/$ORDER_ID"
  curl -s "$BASE_URL/api/v1/orders/$ORDER_ID" \
    -H "Authorization: Bearer $TOKEN" | pretty
  sleep 0.5
  result \
    "Ordine pagato visibile con tutti gli item" \
    "payment_id collegato al pagamento elaborato"
else
  info "ORDER_ID non estratto — controlla il JSON del checkout di step 3"
  sleep 0.5
  result "NON è stato possibile recuperare il dettaglio (ORDER_ID mancante)"
fi

printf "\n${G}${B}✓ Demo Checkout + Saga Compensation completata.${N}\n\n"
