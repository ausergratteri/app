#!/usr/bin/env bash
# =====================================================================
#  AUSER GRATTERI – PROVA DI RIPRISTINO di un backup (solo in locale, nessun accesso a Supabase).
#  Uso:  bash supabase/operazioni/backup/verifica_backup.sh /Volumes/<immagine cifrata>/<cartella>
#  - Controlla l'impronta SHA-256 del dump; lo ripristina in un PostgreSQL 17 usa e getta SENZA RETE
#    (--network none, cartella del backup montata in sola lettura); esegue 00_misure.sql sulla copia;
#    confronta i file salvati (storage/…) con l'elenco di storage.objects del dump: presenza, dimensione,
#    MD5 rispetto all'eTag e all'inventario. Alla fine elimina container e volume.
#  - A schermo solo numeri e messaggi tecnici ripuliti (nessun valore dei dati).
# =====================================================================
set -uo pipefail
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"
cd "$(dirname "$0")/../../.."
DEST="$(node supabase/operazioni/backup/destinazione_cifrata.mjs "${1:?Indicare la cartella del backup}")" || exit 1
DUMP="$(ls -1t "$DEST"/auser-db-*.dump 2>/dev/null | head -1)"; [ -n "$DUMP" ] || { echo "STOP: nessun auser-db-*.dump in $DEST"; exit 1; }
NOME="$(basename "$DUMP")"
( cd "$DEST" && shasum -a 256 -c "$NOME.sha256" >/dev/null 2>&1 ) && echo "impronta del dump: corretta" || { echo "STOP: impronta del dump NON corrisponde"; exit 1; }
N="auser-verifica-backup-$$"
pulisci() { docker rm -fv "$N" >/dev/null 2>&1; }; trap pulisci EXIT
docker run -d --rm --name "$N" --network none -e POSTGRES_HOST_AUTH_METHOD=trust -v "$DEST":/out:ro postgres:17 >/dev/null
for _ in $(seq 60); do docker logs "$N" 2>&1 | grep -q "init process complete" && docker exec "$N" pg_isready -U postgres -q && break; sleep 1; done
q() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$N" psql -U postgres -d ripristino -X -q -t -A "$@"; }
docker exec "$N" createdb -U postgres ripristino
# Ruoli ed estensioni che una copia di Supabase si aspetta (vuoti, senza accesso)
q >/dev/null <<'SQL'
drop schema public cascade;   -- lo ricrea il dump (database appena creato, vuoto)
do $$ declare r text; begin
  foreach r in array array['anon','authenticated','service_role','authenticator','supabase_admin','supabase_auth_admin',
                           'supabase_storage_admin','dashboard_user','supabase_realtime_admin','pgbouncer'] loop
    if not exists (select 1 from pg_roles where rolname = r) then execute format('create role %I nologin', r); end if;
  end loop; end $$;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
SQL
docker exec "$N" pg_restore -U postgres -d ripristino --no-owner --no-privileges "/out/$NOME" > /dev/null 2> "$DEST/$NOME.ripristino.registro"
ERR=$(grep -c "error:" "$DEST/$NOME.ripristino.registro" || true)
echo "ripristino: errori di pg_restore = $ERR"
grep "error:" "$DEST/$NOME.ripristino.registro" | sed -E 's/"[^"]*"/"…"/g; s/(DETAIL|CONTEXT).*//' | cut -c1-150 | sort | uniq -c | head -15
chmod 600 "$DEST/$NOME.ripristino.registro"
echo "== misure sulla copia ripristinata (da confrontare con 00_misure.sql eseguito in produzione)"
q -F' | ' < supabase/operazioni/backup/00_misure.sql
echo "== file di Storage"
q -c "select coalesce(json_agg(json_build_object('b', bucket_id, 'n', name, 's', (metadata->>'size')::bigint, 'e', replace(coalesce(metadata->>'eTag', ''), '\"', ''))), '[]') from storage.objects" \
  | node -e '
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const dest = process.argv[1]; let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
  const db = JSON.parse(s || "[]");
  let inv = []; try { inv = JSON.parse(fs.readFileSync(path.join(dest, "inventario-storage.json"), "utf8")).file; } catch { console.log("inventario-storage.json assente"); }
  const chiave = (b, n) => b + "\u0000" + n, invMap = new Map(inv.map(f => [chiave(f.bucket, f.percorso), f]));
  const r = {nel_database: db.length, presenti: 0, mancanti: 0, dimensione_diversa: 0, md5_diverso_da_etag: 0, md5_diverso_da_inventario: 0, extra_nell_inventario: 0};
  for (const o of db) {
    const p = path.join(dest, "storage", o.b, o.n);
    if (!p.startsWith(path.join(dest, "storage") + path.sep) || !fs.existsSync(p)) { r.mancanti++; continue; }
    r.presenti++;
    const dati = fs.readFileSync(p), md5 = crypto.createHash("md5").update(dati).digest("hex");
    if (o.s !== null && Number(o.s) !== dati.length) r.dimensione_diversa++;
    if (/^[0-9a-f]{32}$/.test(o.e) && o.e !== md5) r.md5_diverso_da_etag++;
    const f = invMap.get(chiave(o.b, o.n)); if (f && f.md5 !== md5) r.md5_diverso_da_inventario++;
    invMap.delete(chiave(o.b, o.n));
  }
  r.extra_nell_inventario = invMap.size;
  console.log(JSON.stringify(r));
  const ok = r.mancanti === 0 && r.dimensione_diversa === 0 && r.md5_diverso_da_etag === 0 && r.md5_diverso_da_inventario === 0 && r.extra_nell_inventario === 0;
  console.log(ok ? "file: TUTTI presenti e integri" : "file: ATTENZIONE, backup dei file incompleto o diverso");
});' "$DEST"
echo "== fine: container e volume eliminati all'uscita; nessun accesso a Supabase"
