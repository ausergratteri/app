#!/usr/bin/env bash
# =====================================================================
#  AUSER GRATTERI – controlli INNOCUI della funzione "registrazione" dopo il deploy (R4).
#  Solo richieste che NON creano account, NON scrivono nel database e NON inviano e-mail:
#  preflight CORS, metodo sbagliato, corpi non validi o incompleti (respinti prima del database),
#  corpo troppo grande, e chiamate dirette alle funzioni del database con la chiave pubblica (negate).
#  Progetto: SOLO quello di config.js (produzione), con l'impronta fissata come in deploy_produzione.sh.
#  Chiave: SOLO quella pubblica di config.js (nessun segreto). A schermo solo codici HTTP ed esiti.
#  Solo per i collaudi locali: AUSER_BASE_PROVA=http://127.0.0.1:<porta> (ammesso solo l'indirizzo locale).
# =====================================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IMPRONTA_PROD="01f443419b5baf940aa39c7a7fcad19176ad0f741469ab76913e8a967484cec2"
U=$(sed -nE 's#.*url: "(https://[a-z0-9]{20}\.supabase\.co)".*#\1#p' "$REPO/config.js" | head -1)
K=$(sed -nE 's#.*chiave: "(sb_publishable_[^"]+)".*#\1#p' "$REPO/config.js" | head -1)
REF=$(echo "$U" | sed -E 's#https://([a-z0-9]{20})\.supabase\.co#\1#')
if [ -n "${AUSER_BASE_PROVA:-}" ]; then
  [[ "$AUSER_BASE_PROVA" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || { echo "STOP: AUSER_BASE_PROVA ammesso solo verso 127.0.0.1"; exit 1; }
  U="$AUSER_BASE_PROVA"
else
  [ "$(printf '%s' "$REF" | shasum -a 256 | cut -d' ' -f1)" = "$IMPRONTA_PROD" ] || { echo "STOP: config.js non indica il progetto di produzione"; exit 1; }
fi
[[ "$K" =~ ^sb_publishable_ ]] || { echo "STOP: chiave pubblica non trovata"; exit 1; }
F="$U/functions/v1/registrazione"; OK="https://ausergratteri.github.io"; ALTRA="https://esempio.org"
T=$(mktemp -d); chmod 700 "$T"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
esito() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'PASS | %-58s | %s\n' "$1" "$2"; else fail=$((fail+1)); printf 'FAIL | %-58s | %s (atteso %s)\n' "$1" "$2" "$3"; fi; }
# richiesta: metodo origine corpo → stampa "codice|ACAO|esito"
richiesta() {
  local metodo="$1" origine="$2" corpo="${3:-}"
  local args=(-s --max-time 30 -X "$metodo" "$F" -H "apikey: $K" -D "$T/h" -o "$T/b" -w '%{http_code}')
  [ -n "$origine" ] && args+=(-H "Origin: $origine")
  [ "$metodo" = "OPTIONS" ] && args+=(-H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type, apikey")
  [ -n "$corpo" ] && args+=(-H "Content-Type: application/json" --data-binary "@$corpo")
  local cod; cod=$(curl "${args[@]}" 2>/dev/null || echo 000)
  local acao; acao=$(grep -i '^access-control-allow-origin:' "$T/h" 2>/dev/null | head -1 | cut -d' ' -f2- | tr -d '\r')
  local es; es=$(node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(j.esito||"-")}catch{console.log("-")}' "$T/b")
  echo "$cod|${acao:-nessuna}|$es"
}
date -u +"inizio %H:%M:%S UTC"
esito "C1 OPTIONS da origine ammessa (CORS)" "$(richiesta OPTIONS "$OK" | cut -d'|' -f1-2)" "204|$OK"
esito "C2 OPTIONS da origine estranea (nessun CORS)" "$(richiesta OPTIONS "$ALTRA" | cut -d'|' -f1-2)" "204|nessuna"
esito "C3 metodo GET" "$(richiesta GET "$OK" | cut -d'|' -f1,3)" "405|metodo_non_consentito"
printf 'non è json' > "$T/c1"; esito "C4 corpo non JSON" "$(richiesta POST "$OK" "$T/c1" | cut -d'|' -f1,3)" "400|dati_non_validi"
printf '{"azione":"sconosciuta"}' > "$T/c2"; esito "C5 azione sconosciuta" "$(richiesta POST "$OK" "$T/c2" | cut -d'|' -f1,3)" "400|dati_non_validi"
printf '{"azione":"avvia"}' > "$T/c3"; esito "C6 avvia senza nome/cognome/telefono (prima del DB)" "$(richiesta POST "$OK" "$T/c3" | cut -d'|' -f1,3)" "400|dati_non_validi"
printf '{"azione":"verifica","richiesta":"x","codice":"1"}' > "$T/c4"; esito "C7 verifica con richiesta non valida (prima del DB)" "$(richiesta POST "$OK" "$T/c4" | cut -d'|' -f1,3)" "400|dati_non_validi"
printf '{"azione":"completa","richiesta":"x","gettone":"y","pin":"1"}' > "$T/c5"; esito "C8 completa con dati non validi (prima del DB)" "$(richiesta POST "$OK" "$T/c5" | cut -d'|' -f1,3)" "400|dati_non_validi"
node -e 'process.stdout.write(JSON.stringify({azione:"avvia",x:"a".repeat(20000)}))' > "$T/c6"; esito "C9 corpo troppo grande" "$(richiesta POST "$OK" "$T/c6" | cut -d'|' -f1,3)" "413|dati_non_validi"
esito "C10 POST da origine estranea: nessuna intestazione CORS" "$(richiesta POST "$ALTRA" "$T/c2" | cut -d'|' -f2)" "nessuna"
for fn in registrazione_avvia registrazione_prenota imposta_email_tesserato annulla_registrazione; do
  printf '{}' > "$T/r"; cod=$(curl -s --max-time 30 -X POST "$U/rest/v1/rpc/$fn" -H "apikey: $K" -H "Content-Type: application/json" --data-binary @"$T/r" -o "$T/b" -w '%{http_code}' 2>/dev/null || echo 000)
  esito "C11 RPC $fn con la chiave pubblica" "$([ "$cod" = 401 ] || [ "$cod" = 403 ] || [ "$cod" = 404 ] && echo negata || echo "accettata $cod")" "negata"
done
date -u +"fine %H:%M:%S UTC"
echo "TOTALE: $pass PASS, $fail FAIL"
echo "Nei registri della funzione attesi: chiave_servizio (fonte), smtp_verifica_ok (DIAGNOSI_SMTP=1), nessun invio_*."
