#!/usr/bin/env bash
# Prova schema.sql e la migrazione su un PostgreSQL usa e getta, senza rete
# (--network none): non contatta Supabase né altri servizi.
#   1. schema.sql nuovo                               → tutti i test devono passare
#   2. schema.sql di main + dati rovinati + migrazione → tutti i test devono passare
#   3. schema.sql di main senza migrazione            → i test devono trovare i difetti
set -euo pipefail
cd "$(dirname "$0")/../.."
IMMAGINE="${PG_IMAGE:-postgres:16-alpine}"
BASE="${BASE_REF:-main}"
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
scenario nuovo $T/00_stub_supabase.sql supabase/schema.sql $T/10_dati_prova.sql $T/20_test_accessi.sql | tee "$TMP/1.txt" | grep -v '^PASS' || true
echo "   $(grep -c '^PASS' "$TMP/1.txt") PASS, $(grep -c '^FAIL' "$TMP/1.txt" || true) FAIL"

echo "== 2. Database esistente ($BASE) + migrazione"
scenario migrato $T/00_stub_supabase.sql "$TMP/schema_vecchio.sql" $T/10_dati_prova.sql $T/15_dati_rovinati.sql \
  supabase/migrations/20261118_sicurezza_accessi.sql $T/20_test_accessi.sql | tee "$TMP/2.txt" | grep -v '^PASS' || true
echo "   $(grep -c '^PASS' "$TMP/2.txt") PASS, $(grep -c '^FAIL' "$TMP/2.txt" || true) FAIL"

echo "== 3. Controllo: schema di $BASE senza correzioni (qui i FAIL sono attesi)"
scenario vecchio $T/00_stub_supabase.sql "$TMP/schema_vecchio.sql" $T/10_dati_prova.sql $T/15_dati_rovinati.sql \
  $T/20_test_accessi.sql > "$TMP/3.txt" || true
echo "   $(grep -c '^PASS' "$TMP/3.txt" || true) PASS, $(grep -c '^FAIL' "$TMP/3.txt" || true) FAIL (difetti trovati)"
grep '^FAIL' "$TMP/3.txt" | cut -d'|' -f2 | sed 's/^/     - /' || true

if grep -q '^FAIL' "$TMP/1.txt" "$TMP/2.txt" || ! grep -q '^PASS' "$TMP/1.txt" || ! grep -q '^PASS' "$TMP/2.txt"; then
  echo "ESITO: test SQL NON superati"; exit 1
fi
echo "ESITO: test SQL superati"
