#!/usr/bin/env bash
# Iscrizioni simultanee: due soci si iscrivono NELLO STESSO MOMENTO all'ultima coppia
# di posti. Con il controllo corretto ne passa una sola; senza, l'attività va oltre i posti.
# Uso: concorrenza.sh <container> <database>   (database già preparato con stub, schema e dati)
set -euo pipefail
C="$1"; DB="$2"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
psql_() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$C" psql -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1 "$@"; }

# Due nuovi soci tesserati e un'attività con 2 posti
psql_ >/dev/null <<'SQL'
insert into public.tesserati (nome, telefono) values ('Socio Uno', '3335550001'), ('Socio Due', '3335550002');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', '3335550001@soci.ausergratteri.app'),
  ('00000000-0000-0000-0000-0000000000a2', '3335550002@soci.ausergratteri.app');
insert into public.attivita (id, titolo, data, posti, ospiti, stato)
  values ('a0000000-0000-0000-0000-0000000000cc', 'Gita con 2 posti', current_date + 10, 2, true, 'aperta');
SQL

iscrivi() {  # utente, attesa prima del commit
  psql_ -t -A <<SQL 2>&1 || true
begin;
select set_config('request.jwt.claim.sub', '$1', true);
set local role authenticated;
insert into public.adesioni (attivita_id, user_id, nome, acc)
  values ('a0000000-0000-0000-0000-0000000000cc', '$1', 'Socio', '[{"nome":"Familiare","rel":"Familiare"}]');
select pg_sleep($2);
commit;
select 'ISCRITTO';
SQL
}
iscrivi 00000000-0000-0000-0000-0000000000a1 2 > "$TMP/1" &
sleep 0.5
iscrivi 00000000-0000-0000-0000-0000000000a2 0 > "$TMP/2" &
wait
ok=$(cat "$TMP/1" "$TMP/2" | grep -c ISCRITTO || true)
esaurito=$(cat "$TMP/1" "$TMP/2" | grep -c 'posti esauriti' || true)
persone=$(psql_ -t -A -c "select coalesce(sum((case when io then 1 else 0 end) + jsonb_array_length(acc)), 0) from public.adesioni where attivita_id = 'a0000000-0000-0000-0000-0000000000cc'")
echo "iscrizioni riuscite=$ok rifiutate=$esaurito persone=$persone posti=2"
if [ "$ok" = 1 ] && [ "$esaurito" = 1 ] && [ "$persone" = 2 ]; then echo "PASS|concorrenza: due iscrizioni simultanee, ne passa una sola"; else echo "FAIL|concorrenza: due iscrizioni simultanee, ne passa una sola"; fi
