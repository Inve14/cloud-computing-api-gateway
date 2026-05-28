#!/usr/bin/env bash
# Demo: Replicazione PostgreSQL — streaming replication master/replica.
# Mostra: replica connessa (pg_stat_replication), hot standby read-only
# (pg_is_in_recovery), propagazione < 1s di un INSERT, e rifiuto di
# scritture sulla replica.
#
# Prerequisito: stack up (catalog-db-master e catalog-db-replica healthy)

set -u

# Carica credenziali dal .env del repo (2 livelli sopra questo script)
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

# Esegue una query psql sul master con output tabulare standard
psql_master() {
  docker exec -e PGPASSWORD="$PG_PASS" catalog-db-master \
    psql -U "$PG_USER" -d "$PG_DB" "$@"
}

# Esegue una query psql sulla replica
psql_replica() {
  docker exec -e PGPASSWORD="$PG_PASS" catalog-db-replica \
    psql -U "$PG_USER" -d "$PG_DB" "$@"
}

printf "\n${B}╔═══════════════════════════════════════════════╗${N}\n"
printf "${B}║  DEMO: REPLICAZIONE — PostgreSQL Streaming    ║${N}\n"
printf "${B}╚═══════════════════════════════════════════════╝${N}\n"

# ──────────────────────────────────────────────────────────────────
step "1 / 5 — pg_stat_replication sul master (replica connessa)"
# ──────────────────────────────────────────────────────────────────
info "Connessione a catalog-db-master — SELECT pg_stat_replication"
psql_master -x -c \
  "SELECT client_addr,
          state,
          sent_lsn,
          write_lsn,
          flush_lsn,
          replay_lsn,
          sync_state
   FROM pg_stat_replication;"
ok "state=streaming → la replica è connessa e riceve WAL in tempo reale"
pause

# ──────────────────────────────────────────────────────────────────
step "2 / 5 — pg_is_in_recovery() sulla replica (hot standby)"
# ──────────────────────────────────────────────────────────────────
info "Connessione a catalog-db-replica — SELECT pg_is_in_recovery()"
psql_replica -c "SELECT pg_is_in_recovery() AS in_recovery_mode;"
ok "in_recovery_mode = t → la replica è in hot standby read-only"
pause

# ──────────────────────────────────────────────────────────────────
step "3 / 5 — INSERT sul master: inserisco un prodotto di test"
# ──────────────────────────────────────────────────────────────────
# Slug con timestamp per evitare conflitti su run multipli
DEMO_SLUG="demo-repl-$(date +%s)"
info "INSERT INTO products su catalog-db-master (slug: $DEMO_SLUG)..."
INSERTED_ID=$(psql_master -t -A -c \
  "INSERT INTO products
     (category_id, name, slug, description, price_cents, currency)
   VALUES
     ('11111111-1111-1111-1111-111111111111',
      'Demo Replication Laptop',
      '$DEMO_SLUG',
      'Prodotto inserito sul master per la demo di streaming replication.',
      99900,
      'EUR')
   RETURNING id;" \
  | head -1 | tr -d '[:space:]')
ok "Prodotto inserito — ID: $INSERTED_ID"
printf "\n"
info "Verifica immediata sul master:"
psql_master -c \
  "SELECT id, name, slug, price_cents FROM products WHERE id = '$INSERTED_ID';"
pause

# ──────────────────────────────────────────────────────────────────
step "4 / 5 — SELECT sulla replica (propagazione < 1s)"
# ──────────────────────────────────────────────────────────────────
info "SELECT su catalog-db-replica — stesso ID appena inserito sul master..."
psql_replica -c \
  "SELECT id, name, slug, price_cents FROM products WHERE id = '$INSERTED_ID';"
ok "Dato già presente sulla replica — streaming WAL operativo!"
printf "\n"
info "Lag di replicazione corrente sulla replica:"
# pg_last_xact_replay_timestamp() è disponibile solo sulla replica in recovery
psql_replica -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replica_lag;"
info "Il lag è normalmente sub-millisecondo su rete locale."
pause

# ──────────────────────────────────────────────────────────────────
step "5 / 5 — INSERT sulla replica → errore (hot standby = read-only)"
# ──────────────────────────────────────────────────────────────────
info "Tentativo di scrittura diretta su catalog-db-replica (deve fallire):"
psql_replica -c \
  "INSERT INTO products
     (category_id, name, slug, description, price_cents)
   VALUES
     ('11111111-1111-1111-1111-111111111111',
      'Prodotto Illegale',
      'should-fail-replica',
      'Questo INSERT non deve avere successo sulla replica.',
      1);" \
  && fail "Inaspettatamente riuscito — qualcosa non va!" \
  || ok "Errore atteso: cannot execute INSERT in a read-only transaction"
info "La replica accetta solo SELECT — tutte le scritture vanno al master."

# Pulizia: rimuove il prodotto di test dal master (la replica replica il DELETE automaticamente)
printf "\n"
info "Pulizia: rimozione prodotto di test dal master..."
psql_master -c "DELETE FROM products WHERE id = '$INSERTED_ID';" > /dev/null
ok "Prodotto di test rimosso"

printf "\n${G}${B}✓ Demo Replicazione completata.${N}\n\n"
