#!/usr/bin/env bash
# Registrazione con OTP: richieste SIMULTANEE con lo stesso gettone o sullo stesso account.
#   1. 10 prenotazioni con lo stesso gettone            → ne passa una sola
#   2. approvazione del direttivo mentre si elimina      → l'eliminazione aspetta e rifiuta
#   3. 5 conferme della stessa prenotazione              → ne passa una sola
# Uso: concorrenza_otp.sh <container> <database>   (database già preparato con stub, schema e dati)
# Lavora SOLO dentro il container indicato (PostgreSQL usa e getta di esegui.sh, senza rete).
set -euo pipefail
C="$1"; DB="$2"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
psql_() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$C" psql -U postgres -d "$DB" -X -q -t -A -v ON_ERROR_STOP=1 "$@"; }
esito() { if [ "$1" = "$2" ]; then echo "PASS|$3"; else echo "FAIL|$3 (ottenuto: $1)"; fi; }

# Tesserati di prova e richieste già verificate: il gettone nasce e resta nel database usa e getta
psql_ >/dev/null <<'SQL'
insert into public.tesserati (nome, telefono) values ('Prova Concorrenza Uno', '3335559001'), ('Prova Concorrenza Due', '3335559002'), ('Prova Concorrenza Tre', '3335559003');
create table public.prova_gettoni (telefono text primary key, richiesta uuid, gettone text);
insert into public.prova_gettoni (telefono, gettone)
  select t, encode(extensions.gen_random_bytes(32), 'hex') from unnest(array['3335559001', '3335559002', '3335559003']) t;
with nuove as (
  insert into registrazione.richieste (tipo, telefono, tesserato_id, verificata_il, token_hash, token_scade_il, ip_hash)
  select 'otp', g.telefono, x.id, now(), encode(extensions.digest(g.gettone, 'sha256'), 'hex'), now() + interval '15 minutes', 'prova-concorrenza'
    from public.prova_gettoni g join public.tesserati x on x.telefono = g.telefono
  returning id, telefono)
update public.prova_gettoni g set richiesta = n.id from nuove n where n.telefono = g.telefono;
-- Account "in attesa" (senza dati) per la prova 2
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000009a2', '3335559002@soci.ausergratteri.app');
SQL
prenota() {  # telefono → esito della prenotazione
  psql_ -c "select esito from public.prova_gettoni g, public.registrazione_prenota(g.richiesta, encode(extensions.digest(g.gettone, 'sha256'), 'hex')) where g.telefono = '$1'" 2>&1 || true
}

prenota_in_tabella() {  # telefono → prenota e conserva la prenotazione nella tabella di prova (resta nel database usa e getta)
  psql_ >/dev/null <<SQL
with p as (
  select g.telefono, x.prenotazione
    from public.prova_gettoni g
    cross join lateral public.registrazione_prenota(g.richiesta, encode(extensions.digest(g.gettone, 'sha256'), 'hex')) x
   where g.telefono = '$1' and x.esito = 'ok')
update public.prova_gettoni g set gettone = p.prenotazione from p where g.telefono = p.telefono;
SQL
}

# 1. 10 prenotazioni simultanee con lo stesso gettone
for i in $(seq 10); do prenota 3335559001 > "$TMP/p$i" & done; wait
ok=$(cat "$TMP"/p* | grep -c '^ok$' || true); no=$(cat "$TMP"/p* | grep -c '^non_valido$' || true)
esito "$ok/$no" "1/9" "concorrenza otp: 10 prenotazioni simultanee con lo stesso gettone → una sola"

# 2. Approvazione del direttivo (riga del profilo bloccata 2 s) mentre si elimina l'account in attesa
prenota_in_tabella 3335559002
psql_ >/dev/null <<'SQL' &
begin;
update public.profili set ruolo = 'socio' where id = '00000000-0000-0000-0000-0000000009a2';
select pg_sleep(2);
commit;
SQL
sleep 0.5
e2=$(psql_ -c "select public.registrazione_elimina_attesa(g.richiesta, g.gettone, '00000000-0000-0000-0000-0000000009a2') from public.prova_gettoni g where g.telefono = '3335559002'" 2>&1 || true)
wait
stato2=$(psql_ -c "select coalesce((select p.ruolo from auth.users u join public.profili p on p.id = u.id where u.id = '00000000-0000-0000-0000-0000000009a2'), 'eliminato')")
esito "$e2/$stato2" "non_valido/socio" "concorrenza otp: approvazione simultanea del direttivo → l'eliminazione rifiuta, l'account resta socio"

# 3. 5 conferme simultanee della stessa prenotazione
prenota_in_tabella 3335559003
psql_ -c "insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000009a3', '3335559003@soci.ausergratteri.app')" >/dev/null
for i in $(seq 5); do
  psql_ -c "select public.registrazione_conferma(g.richiesta, g.gettone, '00000000-0000-0000-0000-0000000009a3') from public.prova_gettoni g where g.telefono = '3335559003'" > "$TMP/c$i" 2>&1 || true &
done; wait
ok3=$(cat "$TMP"/c* | grep -c '^ok$' || true)
ruolo3=$(psql_ -c "select ruolo from public.profili where id = '00000000-0000-0000-0000-0000000009a3'")
esito "$ok3/$ruolo3" "1/socio" "concorrenza otp: 5 conferme simultanee → una sola, account socio"
