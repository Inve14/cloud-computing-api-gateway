#!/usr/bin/env bash
# Demo: Sicurezza — JWT RS256, protezione endpoint, rate limiting Kong.
# Mostra la catena completa: login → token RS256 → protezione /me →
# rifiuto token falsificato → rate limiting su /auth/login.
#
# Prerequisito: stack up e utente admin@example.com esistente (seed incluso)

set -u

BASE_URL="http://localhost:8000"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="Password123!"

source "$(dirname "$0")/_helpers.sh"

# Decodifica il payload base64url del JWT (non verifica la firma — solo ispezione)
decode_jwt_payload() {
  python3 - "$1" << 'PYEOF'
import sys, base64, json
p = sys.argv[1].split('.')[1]
p += '=' * (4 - len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
PYEOF
}

# Esegue una chiamata HTTP e restituisce "body\nHTTP_STATUS:NNN"
http_call() {
  curl -s -w "\n\nHTTP_STATUS:%{http_code}" "$@"
}

split_resp() {
  # $1 = variabile risposta completa
  # Stampa body e ritorna status in HTTP_STATUS
  printf '%s' "$1" | sed '/^HTTP_STATUS:/d'
  HTTP_STATUS=$(printf '%s' "$1" | grep "^HTTP_STATUS:" | cut -d: -f2)
}

printf "\n${B}╔═══════════════════════════════════════════════╗${N}\n"
printf "${B}║   DEMO: SICUREZZA — JWT RS256 + Rate Limiting ║${N}\n"
printf "${B}╚═══════════════════════════════════════════════╝${N}\n"

# ──────────────────────────────────────────────────────────────────
step "1 / 5 — Login admin → JWT RS256 + decodifica payload"
# ──────────────────────────────────────────────────────────────────
intro "Effettuiamo il login dell'utente admin per ottenere un JWT \
firmato RS256, poi decodifichiamo il payload per mostrare i claim \
(iss, role, exp) che Kong userà per validare le richieste successive."
sleep 1

request_info "POST" "$BASE_URL/api/v1/users/auth/login" \
  "Content-Type: application/json" \
  "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"***\"}"
sleep 1

flow_steps \
  "Kong matcha route 'users-auth-login' (pubblica)" \
  "Rate-limit check: 1/10 al minuto per IP — OK" \
  "users-service: authService.login()" \
  "findByEmail → bcrypt.compare(password, hash)" \
  "jwtSign() con chiave privata RSA-2048" \
  "Risposta: access_token + refresh_token"
sleep 1

execute
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/users/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")
printf '%s\n' "$LOGIN_RESP" | pretty

TOKEN=$(printf '%s' "$LOGIN_RESP" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
printf "\n"
info "Payload JWT decodificato (la firma RS256 è verificata da Kong, non dal client):"
decode_jwt_payload "$TOKEN"
sleep 0.5

result \
  "HTTP 200 — token JWT RS256 ottenuto" \
  "Claim 'iss': users-service → Kong la usa per la public key" \
  "Claim 'role'/'exp' presenti — token valido 15 minuti"

pause

# ──────────────────────────────────────────────────────────────────
step "2 / 5 — GET /me senza token → 401 Unauthorized"
# ──────────────────────────────────────────────────────────────────
intro "Tentiamo di accedere a un endpoint protetto SENZA passare il \
token JWT. Ci aspettiamo che Kong rifiuti la richiesta a livello \
gateway, prima ancora che raggiunga il microservizio users."
sleep 1

request_info "GET" "$BASE_URL/api/v1/users/me" \
  "(nessun header Authorization)" ""
sleep 1

flow_steps \
  "Kong matcha route 'users-routes' (catch-all /users/*)" \
  "La route ha il plugin JWT configurato" \
  "Plugin JWT cerca 'Authorization: Bearer' → assente" \
  "Kong ritorna 401 immediatamente, senza forward"
sleep 1

execute
RESP=$(http_call "$BASE_URL/api/v1/users/me")
HTTP_STATUS=$(printf '%s' "$RESP" | grep "^HTTP_STATUS:" | cut -d: -f2)
printf '%s\n' "$RESP" | sed '/^HTTP_STATUS:/d' | pretty
sleep 0.5

if [ "${HTTP_STATUS:-}" = "401" ]; then
  result \
    "HTTP $HTTP_STATUS Unauthorized (risposta da Kong)" \
    "La richiesta NON ha raggiunto il microservizio users" \
    "Filtraggio precoce al gateway: backend risparmiato"
else
  result "FALLITO: HTTP ${HTTP_STATUS:-?} (atteso 401)"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "3 / 5 — GET /me con token falsificato → 401 Unauthorized"
# ──────────────────────────────────────────────────────────────────
intro "Simuliamo un attacco: un client invia un JWT con la stessa \
struttura del token legittimo ma firma RSA inventata. Verifichiamo \
che Kong rifiuti la firma senza inoltrare nulla al servizio."
sleep 1

# Payload: {"sub":"fake-admin","email":"attacker@evil.com","role":"admin","iss":"users-service"}
FAKE_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9\
.eyJzdWIiOiJmYWtlLWFkbWluIiwiZW1haWwiOiJhdHRhY2tlckBldmlsLmNvbSIsInJvbGUiOiJhZG1pbiIsImlzcyI6InVzZXJzLXNlcnZpY2UifQ\
.FIRMA_FALSA_NON_VALIDA_PER_LA_CHIAVE_RSA_PUBBLICA"

request_info "GET" "$BASE_URL/api/v1/users/me" \
  "Authorization: Bearer <token forgiato>" ""
sleep 1

flow_steps \
  "Kong matcha route 'users-routes' (JWT richiesto)" \
  "Plugin JWT decodifica claim 'iss' dal token" \
  "Trova consumer 'default-jwt-consumer' (iss=users-service)" \
  "Verifica firma RSA con la public key configurata" \
  "Firma non valida → Kong ritorna 401, nessun forward"
sleep 1

execute
printf "${C}→  Token forgiato (payload decodificato):${N}\n"
decode_jwt_payload "$FAKE_TOKEN"
printf "\n"

RESP=$(http_call "$BASE_URL/api/v1/users/me" -H "Authorization: Bearer $FAKE_TOKEN")
HTTP_STATUS=$(printf '%s' "$RESP" | grep "^HTTP_STATUS:" | cut -d: -f2)
printf '%s\n' "$RESP" | sed '/^HTTP_STATUS:/d' | pretty
sleep 0.5

if [ "${HTTP_STATUS:-}" = "401" ]; then
  result \
    "HTTP $HTTP_STATUS — firma RSA rifiutata da Kong" \
    "Il payload era ben formato, ma la firma no" \
    "Nessuna richiesta arrivata al microservizio users"
else
  result "FALLITO: HTTP ${HTTP_STATUS:-?} (atteso 401)"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "4 / 5 — GET /me con token valido → 200 OK"
# ──────────────────────────────────────────────────────────────────
intro "Ripetiamo la stessa richiesta con il token legittimo ottenuto \
allo step 1. Questa volta la firma RSA è valida: Kong inoltra la \
richiesta a users-service, che restituisce il profilo dell'utente."
sleep 1

request_info "GET" "$BASE_URL/api/v1/users/me" \
  "Authorization: Bearer <token valido>" ""
sleep 1

flow_steps \
  "Kong matcha route 'users-routes' (JWT richiesto)" \
  "Plugin JWT verifica firma RSA → valida" \
  "Claim 'exp' verificato, token non scaduto" \
  "Richiesta inoltrata a users-service (round-robin)" \
  "users-service: GET /me → SELECT su users DB" \
  "Risposta arricchita con header X-Kong-* / X-Correlation-ID"
sleep 1

execute
RESP=$(http_call "$BASE_URL/api/v1/users/me" -H "Authorization: Bearer $TOKEN")
HTTP_STATUS=$(printf '%s' "$RESP" | grep "^HTTP_STATUS:" | cut -d: -f2)
printf '%s\n' "$RESP" | sed '/^HTTP_STATUS:/d' | pretty
printf "\n"
info "Header Kong nella risposta (latenza gateway vs upstream, correlation id):"
curl -s -D - -o /dev/null "$BASE_URL/api/v1/users/me" \
  -H "Authorization: Bearer $TOKEN" \
  | grep -i "x-kong\|x-correlation\|ratelimit" \
  || info "(nessun header Kong visibile — controlla hide_client_headers=false in kong.yml)"
sleep 0.5

if [ "${HTTP_STATUS:-}" = "200" ]; then
  result \
    "HTTP $HTTP_STATUS — autenticato correttamente" \
    "Header X-Kong-*-Latency separano gateway/upstream" \
    "X-Correlation-ID propagato per il tracing"
else
  result "FALLITO: HTTP ${HTTP_STATUS:-?} (atteso 200)"
fi

pause

# ──────────────────────────────────────────────────────────────────
step "5 / 5 — Rate limiting: 12 login rapidi (Kong: limite 10/min per IP)"
# ──────────────────────────────────────────────────────────────────
intro "Testiamo il rate limiting di Kong sulla route di login (limite \
10 richieste/min per IP). Inviamo 12 tentativi con password errata: \
gli ultimi devono essere bloccati con HTTP 429 prima di users-service."
sleep 1

request_info "POST" "$BASE_URL/api/v1/users/auth/login" \
  "Content-Type: application/json" \
  "{\"email\":\"admin@example.com\",\"password\":\"***\"} (× 12)"
sleep 1

flow_steps \
  "Route 'users-auth-login': rate-limit 10/min per IP" \
  "Plugin conta le richieste nella finestra corrente" \
  "Tentativi entro soglia → forward a users-service" \
  "users-service risponde 401 (credenziali errate)" \
  "Tentativi oltre soglia → Kong risponde 429" \
  "Oltre soglia: users-service NON viene contattato"
sleep 1

execute
info "Attendo l'inizio del prossimo minuto per avere il contatore Kong a zero..."
SECS=$(( 60 - $(date +%S) ))
[ "$SECS" -eq 60 ] && SECS=0
if [ "$SECS" -gt 0 ]; then
  for remaining in $(seq "$SECS" -1 1); do
    printf "\r${C}→  Attendo %2ds...${N}" "$remaining"
    sleep 1
  done
  printf "\r${G}✓  Contatore azzerato!                          ${N}\n"
fi
printf "\n"
info "Invio 12 login con password errata (limite Kong: 10/min per IP)..."
RATE_LIMITED_SEEN=0
for i in $(seq 1 12); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/users/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@example.com","password":"WRONG_PASSWORD_DEMO"}')
  if [ "$STATUS" = "429" ]; then
    RATE_LIMITED_SEEN=1
    printf "${R}✗  Tentativo %2d → HTTP %s  ←  RATE LIMITED da Kong!${N}\n" "$i" "$STATUS"
  elif [ "$STATUS" = "401" ]; then
    printf "${G}✓  Tentativo %2d → HTTP %s  (credenziali errate, ancora entro il limite)${N}\n" "$i" "$STATUS"
  else
    printf "${C}→  Tentativo %2d → HTTP %s${N}\n" "$i" "$STATUS"
  fi
done
printf "\n"
info "Header rate limit nell'ultima risposta 429:"
curl -s -D - -o /dev/null \
  -X POST "$BASE_URL/api/v1/users/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"WRONG"}' \
  | grep -i "ratelimit\|retry-after\|x-kong" \
  || info "(nessun header visibile — il limite potrebbe essere già scaduto)"
sleep 0.5

if [ "$RATE_LIMITED_SEEN" = "1" ]; then
  result \
    "Rate limit raggiunto: alcuni tentativi → HTTP 429" \
    "Le richieste oltre soglia non hanno raggiunto users-service" \
    "Header RateLimit-*/Retry-After indicano il reset"
else
  result \
    "NON osservato HTTP 429 in questa run" \
    "Il contatore Kong potrebbe essere già alto da run precedenti"
fi

printf "\n${G}${B}✓ Demo Sicurezza completata.${N}\n\n"
