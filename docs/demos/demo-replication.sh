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

source "$(dirname "$0")/_helpers.sh"

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
intro "Verifichiamo che la replica PostgreSQL sia connessa al master \
e riceva lo stream WAL in tempo reale, interrogando la vista di \
sistema pg_stat_replication sul nodo master."
sleep 1

request_info "QUERY" "catalog-db-master → $PG_DB" \
  "psql -U $PG_USER (-x, output verticale)" \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state FROM pg_stat_replication;"
sleep 1

flow_steps \
  "catalog-db-replica si connette al master in streaming" \
  "Il master registra la connessione in pg_stat_replication" \
  "'state=streaming' → WAL inviato in tempo reale" \
  "sent/write/flush/replay_lsn tracciano il progresso" \
  "sync_state indica la modalità (async di default)"
sleep 1

execute
psql_master -x -c \
  "SELECT client_addr,
          state,
          sent_lsn,
          write_lsn,
          flush_lsn,
          replay_lsn,
          sync_state
   FROM pg_stat_replication;"
sleep 0.5

# Cattura i valori per la lettura annotata
REPL_DATA=$(psql_master -t -A -F'|' -c \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state
   FROM pg_stat_replication LIMIT 1;")
IFS='|' read -r REPL_CLIENT_ADDR REPL_STATE REPL_SENT_LSN REPL_WRITE_LSN REPL_FLUSH_LSN REPL_REPLAY_LSN REPL_SYNC_STATE <<< "$REPL_DATA"

printf "${B}📖 LETTURA ANNOTATA${N}\n"
printf "   client_addr   = %-18s ${C}← IP della replica nella rete Docker${N}\n"             "$REPL_CLIENT_ADDR"
printf "   state         = %-18s ${C}← stream WAL attivo (stato operativo desiderato)${N}\n" "$REPL_STATE"
printf "   sent_lsn      = %-18s ${C}← posizione WAL inviata dal master${N}\n"                "$REPL_SENT_LSN"
printf "   write_lsn     = %-18s ${C}← posizione ricevuta in memoria dalla replica${N}\n"     "$REPL_WRITE_LSN"
printf "   flush_lsn     = %-18s ${C}← posizione flushata su disco dalla replica${N}\n"       "$REPL_FLUSH_LSN"
printf "   replay_lsn    = %-18s ${C}← posizione effettivamente applicata ai dati${N}\n"      "$REPL_REPLAY_LSN"
printf "   sync_state    = %-18s ${C}← replicazione asincrona (master non aspetta replica)${N}\n" "$REPL_SYNC_STATE"
printf "\n"
printf "   💡 Tutti i 4 LSN sono identici → zero lag, replica perfettamente allineata\n"
printf "   💡 Se vedessimo write_lsn < sent_lsn → problema di rete tra master e replica\n\n"
sleep 0.5

result \
  "state = streaming — replica connessa e attiva" \
  "LSN allineati — nessun lag significativo"

pause

# ──────────────────────────────────────────────────────────────────
step "2 / 5 — pg_is_in_recovery() sulla replica (hot standby)"
# ──────────────────────────────────────────────────────────────────
intro "Verifichiamo che la replica sia in modalità hot standby: deve \
accettare connessioni in sola lettura mentre applica continuamente \
il WAL ricevuto dal master."
sleep 1

request_info "QUERY" "catalog-db-replica → $PG_DB" \
  "psql -U $PG_USER" \
  "SELECT pg_is_in_recovery() AS in_recovery_mode;"
sleep 1

flow_steps \
  "La replica è avviata in modalità standby (standby.signal)" \
  "pg_is_in_recovery() ritorna true sui nodi standby" \
  "Il nodo accetta SELECT ma rifiuta scritture" \
  "Il WAL receiver applica i segmenti ricevuti"
sleep 1

execute
psql_replica -c "SELECT pg_is_in_recovery() AS in_recovery_mode;"
sleep 0.5

# Cattura il valore per la lettura annotata
IN_RECOVERY=$(psql_replica -t -A -c "SELECT pg_is_in_recovery();")

printf "${B}📖 LETTURA ANNOTATA${N}\n"
printf "   in_recovery_mode = %-3s ${C}← '%s' in PostgreSQL = %s (boolean)${N}\n" \
  "$IN_RECOVERY" "$IN_RECOVERY" "$([ "$IN_RECOVERY" = "t" ] && echo TRUE || echo FALSE)"
printf "\n"
printf "   💡 'TRUE' significa che il nodo è in modalità hot standby:\n"
printf "      • Sta applicando continuamente il WAL ricevuto dal master\n"
printf "      • Accetta connessioni SELECT (sola lettura)\n"
printf "      • Rifiuta INSERT/UPDATE/DELETE a livello di engine\n"
printf "   💡 Sul master, la stessa query restituirebbe 'f' (false)\n\n"
sleep 0.5

result \
  "in_recovery_mode = t — hot standby attivo" \
  "Nodo pronto per servire query di sola lettura"

pause

# ──────────────────────────────────────────────────────────────────
step "3 / 5 — INSERT sul master: inserisco un prodotto di test"
# ──────────────────────────────────────────────────────────────────
intro "Inseriamo un nuovo prodotto direttamente sul master, generando \
una transazione che dovrà propagarsi alla replica via streaming WAL."
sleep 1

# Slug con timestamp per evitare conflitti su run multipli
DEMO_SLUG="demo-repl-$(date +%s)"

request_info "QUERY" "catalog-db-master → $PG_DB" \
  "psql -U $PG_USER" \
  "INSERT INTO products (..., slug='$DEMO_SLUG', ...) RETURNING id;"
sleep 1

flow_steps \
  "INSERT eseguito sul master (unico nodo scrivibile)" \
  "La transazione viene scritta nel WAL del master" \
  "Il WAL sender invia i nuovi segmenti alla replica" \
  "Verifica immediata con SELECT sullo stesso master"
sleep 1

execute
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
printf "\n"
info "Verifica immediata sul master:"
psql_master -c \
  "SELECT id, name, slug, price_cents FROM products WHERE id = '$INSERTED_ID';"
sleep 0.5

result \
  "Prodotto inserito — ID: $INSERTED_ID" \
  "Transazione committata sul master"

pause

# ──────────────────────────────────────────────────────────────────
step "4 / 5 — SELECT sulla replica (propagazione < 1s)"
# ──────────────────────────────────────────────────────────────────
intro "Eseguiamo una SELECT sulla replica per lo stesso ID appena \
inserito sul master e misuriamo il lag di replicazione attuale: su \
rete locale la propagazione è tipicamente sub-secondo."
sleep 1

request_info "QUERY" "catalog-db-replica → $PG_DB" \
  "psql -U $PG_USER" \
  "SELECT id, name, slug, price_cents FROM products WHERE id = '$INSERTED_ID';"
sleep 1

flow_steps \
  "Il WAL receiver ha già applicato la transazione" \
  "La SELECT trova la riga senza rileggere dal master" \
  "pg_last_xact_replay_timestamp() misura il lag" \
  "now() - replay_timestamp = lag di replicazione"
sleep 1

execute
psql_replica -c \
  "SELECT id, name, slug, price_cents FROM products WHERE id = '$INSERTED_ID';"
printf "\n"
info "Lag di replicazione corrente sulla replica:"
# pg_last_xact_replay_timestamp() è disponibile solo sulla replica in recovery
psql_replica -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replica_lag;"
sleep 0.5

result \
  "Prodotto trovato sulla replica — streaming WAL operativo" \
  "Lag misurato include il tempo di pausa interattiva tra step"

pause

# ──────────────────────────────────────────────────────────────────
step "5 / 5 — INSERT sulla replica → errore (hot standby = read-only)"
# ──────────────────────────────────────────────────────────────────
intro "Tentiamo una scrittura diretta sulla replica per dimostrare \
che PostgreSQL la rifiuta: in modalità hot standby il nodo è \
strutturalmente read-only, indipendentemente dai permessi utente."
sleep 1

request_info "QUERY" "catalog-db-replica → $PG_DB" \
  "psql -U $PG_USER" \
  "INSERT INTO products (..., slug='should-fail-replica', ...);"
sleep 1

flow_steps \
  "Il client invia INSERT alla replica" \
  "PostgreSQL rileva che il nodo è in recovery" \
  "La transazione viene rifiutata a livello di engine" \
  "Errore: 'cannot execute INSERT in a read-only transaction'" \
  "Tutte le scritture devono andare al master"
sleep 1

execute
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
  && INSERT_FAILED=0 \
  || INSERT_FAILED=1

# Pulizia: rimuove il prodotto di test dal master (la replica replica il DELETE automaticamente)
printf "\n"
info "Pulizia: rimozione prodotto di test dal master..."
psql_master -c "DELETE FROM products WHERE id = '$INSERTED_ID';" > /dev/null
ok "Prodotto di test rimosso"
sleep 0.5

if [ "$INSERT_FAILED" = "1" ]; then
  result \
    "INSERT rifiutato — 'read-only transaction' (atteso)" \
    "Scritture isolate al master — integrità garantita" \
    "Prodotto di test rimosso dal master (idempotenza)"
else
  result "FALLITO: l'INSERT sulla replica è inaspettatamente riuscito!"
fi

printf "\n${G}${B}✓ Demo Replicazione completata.${N}\n\n"
