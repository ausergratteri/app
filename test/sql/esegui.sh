#!/usr/bin/env bash
# Prova schema.sql e la migrazione su un PostgreSQL usa e getta, senza rete
# (--network none): non contatta Supabase né altri servizi.
#   1. schema.sql nuovo                               → tutti i test devono passare
#   2. schema.sql di main + dati rovinati + migrazione → tutti i test devono passare
#   3. schema.sql di main senza migrazione            → i test devono trovare i difetti
#   4. trasferimento delle foto (06) e rollback (05)  → tutti i test devono passare
#   5. due iscrizioni simultanee agli ultimi posti    → ne deve passare una sola
#   6. permessi sulle foto per ruolo (20261121): schema in produzione + migrazione,
#      dati invariati, migrazione rieseguibile, blocco con regole sconosciute, rollback
# I riferimenti di confronto sono commit fissi (main oggi contiene già le correzioni):
#   BASE_REF            schema prima di tutte le correzioni di sicurezza
#   CONFRONTO_REF       schema prima della correzione dei posti
#   PRIMA_PERMESSI_REF  schema oggi in produzione, prima di 20261121
set -euo pipefail
cd "$(dirname "$0")/../.."
IMMAGINE="${PG_IMAGE:-postgres:16-alpine}"
BASE="${BASE_REF:-1951fbe}"
PRIMA_PERMESSI="${PRIMA_PERMESSI_REF:-055c922}"
NOME="auser-test-sql-$$"
TMP="$(mktemp -d)"

docker run -d --rm --name "$NOME" --network none -e POSTGRES_HOST_AUTH_METHOD=trust "$IMMAGINE" >/dev/null
trap 'docker rm -f "$NOME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
for _ in $(seq 60); do
  docker logs "$NOME" 2>&1 | grep -q "init process complete" && docker exec "$NOME" pg_isready -U postgres -q && break
  sleep 1
done

git show "$BASE:supabase/schema.sql" > "$TMP/schema_vecchio.sql"
T=test/sql
scenario() {  # nome file...
  local db="$1"; shift
  docker exec "$NOME" createdb -U postgres "$db"
  cat "$@" | docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$NOME" psql -U postgres -d "$db" -v ON_ERROR_STOP=1 -q -X 2>&1
}

echo "== 1. Installazione nuova (supabase/schema.sql)"
scenario nuovo $T/00_stub_supabase.sql supabase/schema.sql $T/10_dati_prova.sql $T/20_test_accessi.sql $T/25_test_posti.sql \
  $T/30_test_importazione.sql $T/40_test_foto_private.sql $T/45_test_permessi_foto.sql | tee "$TMP/1.txt" | grep -v '^PASS' || true
echo "   $(grep -c '^PASS' "$TMP/1.txt") PASS, $(grep -c '^FAIL' "$TMP/1.txt" || true) FAIL"

echo "== 2. Database esistente ($BASE) + migrazione"
scenario migrato $T/00_stub_supabase.sql "$TMP/schema_vecchio.sql" $T/10_dati_prova.sql $T/15_dati_rovinati.sql \
  supabase/migrations/20261118_sicurezza_accessi.sql supabase/migrations/20261119_importa_tesserati.sql \
  supabase/migrations/20261120_foto_private.sql supabase/migrations/20261121_permessi_foto_ruoli.sql \
  $T/20_test_accessi.sql $T/25_test_posti.sql $T/30_test_importazione.sql $T/40_test_foto_private.sql \
  $T/45_test_permessi_foto.sql | tee "$TMP/2.txt" | grep -v '^PASS' || true
echo "   $(grep -c '^PASS' "$TMP/2.txt") PASS, $(grep -c '^FAIL' "$TMP/2.txt" || true) FAIL"

echo "== 3. Controllo: schema di $BASE senza correzioni (qui i FAIL sono attesi)"
scenario vecchio $T/00_stub_supabase.sql "$TMP/schema_vecchio.sql" $T/10_dati_prova.sql $T/15_dati_rovinati.sql \
  $T/20_test_accessi.sql > "$TMP/3.txt" || true
echo "   $(grep -c '^PASS' "$TMP/3.txt" || true) PASS, $(grep -c '^FAIL' "$TMP/3.txt" || true) FAIL (difetti trovati)"
grep '^FAIL' "$TMP/3.txt" | cut -d'|' -f2 | sed 's/^/     - /' || true

echo "== 4. Trasferimento delle foto nel bucket privato e rollback"
O=supabase/operazioni
scenario trasferimento $T/00_stub_supabase.sql supabase/schema.sql $T/10_dati_prova.sql $T/20_test_accessi.sql \
  $T/50_trasferimento_prepara.sql $O/06_attiva_foto_private.sql $O/06_attiva_foto_private.sql $T/51_trasferimento_dopo_attivazione.sql \
  $O/05_rollback_foto_private.sql $T/52_trasferimento_rollback_bloccato.sql $O/05_rollback_foto_private.sql \
  $T/53_trasferimento_dopo_rollback.sql > "$TMP/4.txt" 2>&1 || true
grep -q 'non hanno più la copia pubblica' "$TMP/4.txt" && echo "PASS|rollback: bloccato con il messaggio atteso" >> "$TMP/4.txt" \
  || echo "FAIL|rollback: il blocco non ha dato il messaggio atteso" >> "$TMP/4.txt"
grep -E '^(FAIL|ERROR|psql:)' "$TMP/4.txt" | grep -v 'non hanno più la copia pubblica' | grep -v 'current transaction is aborted' || true
echo "   $(grep -c '^PASS' "$TMP/4.txt") PASS, $(grep -c '^FAIL' "$TMP/4.txt" || true) FAIL"

echo "== 5. Iscrizioni simultanee agli ultimi posti"
docker exec "$NOME" createdb -U postgres concorrenza
cat $T/00_stub_supabase.sql supabase/schema.sql $T/10_dati_prova.sql | docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$NOME" psql -U postgres -d concorrenza -v ON_ERROR_STOP=1 -q -X >/dev/null
bash $T/concorrenza.sh "$NOME" concorrenza | tee "$TMP/5.txt" | sed 's/^/   /'
if git cat-file -e "${CONFRONTO_REF:-6e3d028}:supabase/schema.sql" 2>/dev/null; then
  echo "   controllo: schema di ${CONFRONTO_REF:-6e3d028} (prima della correzione; qui il FAIL è atteso)"
  git show "${CONFRONTO_REF:-6e3d028}:supabase/schema.sql" > "$TMP/schema_conf.sql"
  docker exec "$NOME" createdb -U postgres concorrenza_prima
  cat $T/00_stub_supabase.sql "$TMP/schema_conf.sql" $T/10_dati_prova.sql | docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$NOME" psql -U postgres -d concorrenza_prima -v ON_ERROR_STOP=1 -q -X >/dev/null
  bash $T/concorrenza.sh "$NOME" concorrenza_prima | sed 's/^/     /'
fi

echo "== 6. Permessi sulle foto per ruolo: schema in produzione ($PRIMA_PERMESSI) + 20261121"
git show "$PRIMA_PERMESSI:supabase/schema.sql" > "$TMP/schema_prod.sql"
M=supabase/migrations/20261121_permessi_foto_ruoli.sql
q() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$NOME" psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -q -X -At 2>&1; }
IMPRONTA_DATI="select md5(coalesce((select string_agg(f::text, '|' order by f.id) from public.foto f), '') || coalesce((select string_agg(o.bucket_id || o.name || coalesce(o.metadata::text, ''), '|' order by o.bucket_id, o.name) from storage.objects o), ''))"
IMPRONTA_REGOLE="select md5(string_agg(concat_ws('|', schemaname, tablename, policyname, permissive, cmd, roles::text, qual, with_check), E'\\n' order by schemaname, tablename, policyname)) from pg_policies where (schemaname, tablename) in (('public', 'foto'), ('storage', 'objects'))"
esito6() { if [ "$1" = "$2" ]; then echo "PASS|$3"; else echo "FAIL|$3"; fi; }
{
  for db in permessi permessi_prima permessi_intrusa; do
    docker exec "$NOME" createdb -U postgres "$db"
    cat $T/00_stub_supabase.sql "$TMP/schema_prod.sql" $T/10_dati_prova.sql $T/20_test_accessi.sql $T/40_test_foto_private.sql | q "$db" >/dev/null
  done
  dati_prima=$(echo "$IMPRONTA_DATI" | q permessi); regole_prima=$(echo "$IMPRONTA_REGOLE" | q permessi)
  q permessi < "$M" && q permessi < "$M" && echo "PASS|migrazione: eseguita due volte senza errori" || echo "FAIL|migrazione: errore"
  esito6 "$dati_prima" "$(echo "$IMPRONTA_DATI" | q permessi)" "migrazione: righe di public.foto e file in storage.objects invariati"
  [ "$regole_prima" != "$(echo "$IMPRONTA_REGOLE" | q permessi)" ] && echo "PASS|migrazione: le regole sono cambiate" || echo "FAIL|migrazione: le regole non sono cambiate"
  # Regola sconosciuta (per esempio creata a mano dal pannello): la migrazione si ferma senza cambiare nulla
  echo "create policy aggiunta_a_mano on storage.objects for select to authenticated using (true);" | q permessi_intrusa
  regole_intrusa=$(echo "$IMPRONTA_REGOLE" | q permessi_intrusa)
  out=$(q permessi_intrusa < "$M" || true)
  echo "$out" | grep -q "Regole sconosciute.*aggiunta_a_mano" && echo "PASS|migrazione: si ferma e nomina la regola sconosciuta" || echo "FAIL|migrazione: non si è fermata davanti alla regola sconosciuta"
  esito6 "$regole_intrusa" "$(echo "$IMPRONTA_REGOLE" | q permessi_intrusa)" "migrazione: fermata, le regole sono rimaste com'erano"
  # Test per ruolo dopo la migrazione (il file 45 aggiunge dati di prova: va dopo il controllo dei dati)
  q permessi < $T/45_test_permessi_foto.sql | grep -E '^(PASS|FAIL)'
  # Rollback: le regole tornano identiche a prima della migrazione
  q permessi < supabase/operazioni/08_rollback_permessi_foto.sql >/dev/null
  esito6 "$regole_prima" "$(echo "$IMPRONTA_REGOLE" | q permessi)" "rollback: regole identiche a prima della migrazione"
} > "$TMP/6.txt"
grep -v '^PASS' "$TMP/6.txt" || true
echo "   $(grep -c '^PASS' "$TMP/6.txt") PASS, $(grep -c '^FAIL' "$TMP/6.txt" || true) FAIL"
echo "   controllo: schema in produzione senza 20261121 (qui i FAIL sono attesi)"
q permessi_prima < $T/45_test_permessi_foto.sql > "$TMP/6b.txt" || true
echo "     $(grep -c '^PASS' "$TMP/6b.txt" || true) PASS, $(grep -c '^FAIL' "$TMP/6b.txt" || true) FAIL (difetti trovati)"
grep '^FAIL' "$TMP/6b.txt" | cut -d'|' -f2 | sed 's/^/       - /' || true

if grep -q '^FAIL' "$TMP/1.txt" "$TMP/2.txt" "$TMP/4.txt" "$TMP/5.txt" "$TMP/6.txt" || ! grep -q '^PASS' "$TMP/1.txt" || ! grep -q '^PASS' "$TMP/2.txt" \
   || ! grep -q '^PASS' "$TMP/4.txt" || ! grep -q '^PASS' "$TMP/5.txt" || ! grep -q '^PASS' "$TMP/6.txt"; then
  echo "ESITO: test SQL NON superati"; exit 1
fi
echo "ESITO: test SQL superati"
