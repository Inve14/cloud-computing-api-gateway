#!/usr/bin/env bash
# Helper comuni per le demo (docs/demos/*.sh).
#
# Fornisce:
#   - colori ANSI condivisi
#   - funzioni di stampa di base (step, ok, fail, info, pause, pretty)
#   - funzioni per il formato narrativo a 5 sezioni usato in ogni step:
#       intro          → 📋 COSA STIAMO PER FARE
#       request_info   → 📤 RICHIESTA INVIATA
#       flow_steps     → 🔄 FLUSSO INTERNO
#       execute        → ⚙️  ESECUZIONE (intestazione, output segue)
#       result         → 📥 RISULTATO
#
# Uso: source "$(dirname "$0")/_helpers.sh"

# ---------- Colori ANSI ----------
G='\033[0;32m'  # verde   → OK
R='\033[0;31m'  # rosso   → FAIL
Y='\033[1;33m'  # giallo  → step header
C='\033[0;36m'  # cyan    → info
B='\033[1m'     # bold
N='\033[0m'     # reset

step()  { printf "\n${Y}═══════════════════════════════════════════════${N}\n${Y}  %s${N}\n${Y}═══════════════════════════════════════════════${N}\n\n" "$1"; }
ok()    { printf "${G}✓  %s${N}\n" "$1"; }
fail()  { printf "${R}✗  %s${N}\n" "$1"; }
info()  { printf "${C}→  %s${N}\n" "$1"; }
pause() { printf "\n"; read -rp "$(printf "${B}[INVIO per continuare...]${N}") " _; printf "\n"; }
pretty(){ python3 -m json.tool 2>/dev/null || cat; }

# 📋 COSA STIAMO PER FARE — intro narrativa allo step (italiano discorsivo,
# va a capo automaticamente a 65 colonne).
intro() {
  printf "${B}📋 COSA STIAMO PER FARE${N}\n"
  printf '%s\n' "$1" | fold -s -w 65 | while IFS= read -r line; do
    printf "   %s\n" "$line"
  done
  printf "\n"
}

# 📤 RICHIESTA INVIATA — dettaglio della chiamata che sta per partire.
# Per step non-HTTP (query SQL, chiamate Admin API) i campi Method/URL/Headers
# vengono riusati liberamente (es. Method="QUERY", URL="<db> → <schema>").
request_info() {
  local method="$1" url="$2" headers="$3" body="${4:-}"
  printf "${B}📤 RICHIESTA INVIATA${N}\n"
  printf "   Method:  ${C}%s${N}\n" "$method"
  printf "   URL:     ${C}%s${N}\n" "$url"
  [ -n "$headers" ] && printf "   Headers: %s\n" "$headers"
  [ -n "$body" ] && printf "   Body:    %s\n" "$body"
  printf "\n"
}

# 🔄 FLUSSO INTERNO — passi numerati di cosa succede dietro le quinte
# (Kong, microservizi, DB). Max ~60-65 caratteri per riga.
flow_steps() {
  printf "${B}🔄 FLUSSO INTERNO${N}\n"
  local i=1
  for step_text in "$@"; do
    printf "   %d. %s\n" "$i" "$step_text"
    i=$((i + 1))
  done
  printf "\n"
}

# ⚙️  ESECUZIONE — intestazione prima dell'output reale del comando
# (l'unica sezione "dinamica": JSON, log, output psql, ecc.)
execute() {
  printf "${B}⚙️  ESECUZIONE${N}\n"
}

# 📥 RISULTATO — interpretazione sintetica dei risultati osservati.
# Le righe che iniziano con ✗, ERRORE, FALLITO o "NON " vengono evidenziate
# in rosso con ✗; tutte le altre in verde con ✓.
result() {
  printf "${B}📥 RISULTATO${N}\n"
  for line in "$@"; do
    if printf '%s' "$line" | grep -q '^✗\|^ERRORE\|FALLITO\|NON '; then
      printf "   ${R}✗  %s${N}\n" "$line"
    else
      printf "   ${G}✓  %s${N}\n" "$line"
    fi
  done
  printf "\n"
}
