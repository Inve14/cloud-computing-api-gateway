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
info "POST /api/v1/users/auth/login (admin@example.com)"
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/users/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")
printf '%s\n' "$LOGIN_RESP" | pretty

TOKEN=$(printf '%s' "$LOGIN_RESP" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
ok "Token JWT estratto"
printf "\n"
info "Payload JWT decodificato (base64url — la firma RS256 è verificata da Kong, non dal client):"
decode_jwt_payload "$TOKEN"
info "Il campo 'iss' (users-service) è la chiave che Kong usa per trovare la public key RSA."
pause

# ──────────────────────────────────────────────────────────────────
step "2 / 5 — GET /me senza token → 401 Unauthorized"
# ──────────────────────────────────────────────────────────────────
info "GET /api/v1/users/me — nessun Authorization header"
RESP=$(http_call "$BASE_URL/api/v1/users/me")
split_resp "$RESP" | pretty
if [ "${HTTP_STATUS:-}" = "401" ]; then
  ok "HTTP $HTTP_STATUS — Kong rifiuta la richiesta senza token (prima che arrivi al servizio)"
fi
pause

# ──────────────────────────────────────────────────────────────────
step "3 / 5 — GET /me con token falsificato → 401 Unauthorized"
# ──────────────────────────────────────────────────────────────────
info "Un attaccante prova a forgiare un JWT (stessa struttura, firma inventata)"
# Payload: {"sub":"fake-admin","email":"attacker@evil.com","role":"admin","iss":"users-service"}
FAKE_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9\
.eyJzdWIiOiJmYWtlLWFkbWluIiwiZW1haWwiOiJhdHRhY2tlckBldmlsLmNvbSIsInJvbGUiOiJhZG1pbiIsImlzcyI6InVzZXJzLXNlcnZpY2UifQ\
.FIRMA_FALSA_NON_VALIDA_PER_LA_CHIAVE_RSA_PUBBLICA"

printf "${C}→  Token forgiato (payload decodificato):${N}\n"
decode_jwt_payload "$FAKE_TOKEN"
printf "\n"

RESP=$(http_call "$BASE_URL/api/v1/users/me" -H "Authorization: Bearer $FAKE_TOKEN")
split_resp "$RESP" | pretty
if [ "${HTTP_STATUS:-}" = "401" ]; then
  ok "HTTP $HTTP_STATUS — Kong rifiuta il token: firma RSA non valida"
fi
pause

# ──────────────────────────────────────────────────────────────────
step "4 / 5 — GET /me con token valido → 200 OK"
# ──────────────────────────────────────────────────────────────────
info "GET /api/v1/users/me — Authorization: Bearer <token legittimo>"
RESP=$(http_call "$BASE_URL/api/v1/users/me" -H "Authorization: Bearer $TOKEN")
split_resp "$RESP" | pretty
if [ "${HTTP_STATUS:-}" = "200" ]; then
  ok "HTTP $HTTP_STATUS — autenticato correttamente"
fi
printf "\n"
info "Header Kong nella risposta (distingue latenza gateway vs upstream):"
curl -s -D - -o /dev/null "$BASE_URL/api/v1/users/me" \
  -H "Authorization: Bearer $TOKEN" \
  | grep -i "x-kong\|x-correlation\|ratelimit" \
  || info "(nessun header Kong visibile — controlla che hide_client_headers=false in kong.yml)"
pause

# ──────────────────────────────────────────────────────────────────
step "5 / 5 — Rate limiting: 12 login rapidi (Kong: limite 10/min per IP)"
# ──────────────────────────────────────────────────────────────────
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
for i in $(seq 1 12); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/users/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@example.com","password":"WRONG_PASSWORD_DEMO"}')
  if [ "$STATUS" = "429" ]; then
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

printf "\n${G}${B}✓ Demo Sicurezza completata.${N}\n\n"
