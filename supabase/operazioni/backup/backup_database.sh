#!/usr/bin/env bash
# =====================================================================
#  AUSER GRATTERI – backup del DATABASE di produzione (sola lettura sul database).
#  Uso (nel Terminale dell'amministratore, dalla cartella del repository):
#     bash supabase/operazioni/backup/backup_database.sh /Volumes/<immagine cifrata>/<cartella>
#  - La destinazione DEVE essere su un'immagine disco CIFRATA montata in /Volumes (controllo con hdiutil).
#  - Chiede host e utente del "Session pooler" (Supabase → Connect) e la password del database,
#    senza mostrarla; l'utente deve essere postgres.<identificativo di config.js> (produzione).
#  - pg_dump 17 in un container Docker usa e getta, formato custom (-Fc), schemi:
#    public, auth, storage, registrazione (richieste OTP e funzioni della registrazione) e backup_*
#    (dati, struttura, regole, funzioni, trigger, permessi).
#  - Alla fine: impronta SHA-256, controllo che l'archivio sia leggibile, numero di tabelle con dati.
#  Non stampa dati, password o chiavi. Non modifica nulla in produzione.
# =====================================================================
set -euo pipefail
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"
cd "$(dirname "$0")/../../.."                                   # radice del repository
DEST_ARG="${1:?Indicare la cartella di destinazione, su una immagine cifrata montata in /Volumes}"
# 1. Destinazione su un'immagine disco cifrata montata (controllo con hdiutil)
DEST="$(node supabase/operazioni/backup/destinazione_cifrata.mjs "$DEST_ARG")" || exit 1
# 2. Progetto di produzione (identificativo pubblico, da config.js)
REF=$(grep -oE 'https://[a-z0-9]+\.supabase\.co' config.js | head -1 | sed -E 's#https://([a-z0-9]+)\.supabase\.co#\1#')
[[ "$REF" =~ ^[a-z0-9]{20}$ ]] || { echo "STOP: identificativo del progetto non trovato in config.js"; exit 1; }
read -r -p "Host del Session pooler (es. aws-0-eu-central-1.pooler.supabase.com): " HOST
read -r -p "Utente (postgres.<identificativo>): " UTENTE
[[ "$UTENTE" == "postgres.$REF" ]] || { echo "STOP: l'utente non è quello del progetto di produzione indicato in config.js"; exit 1; }
[[ "$HOST" =~ ^[a-z0-9.-]+$ ]] || { echo "STOP: host non valido"; exit 1; }
read -r -s -p "Password del database (non viene mostrata): " PGPASSWORD; echo
export PGPASSWORD PGSSLMODE="${PGSSLMODE:-require}"
trap 'unset PGPASSWORD' EXIT
ORA=$(date +%Y%m%d-%H%M); NOME="auser-db-$ORA.dump"
umask 077
echo "Backup in corso (sola lettura sul database)…"
docker run --rm -e PGPASSWORD -e PGSSLMODE -v "$DEST":/out postgres:17 \
  pg_dump -h "$HOST" -p 5432 -U "$UTENTE" -d postgres -Fc -Z 6 \
    -n public -n auth -n storage -n registrazione -n 'backup_*' -f "/out/$NOME" 2> "$DEST/$NOME.registro" \
  || { echo "STOP: pg_dump non riuscito (dettagli tecnici in $DEST/$NOME.registro, senza password)"; exit 1; }
unset PGPASSWORD
chmod 600 "$DEST/$NOME"
# 3. Controlli sull'archivio (senza dati a schermo)
( cd "$DEST" && shasum -a 256 "$NOME" > "$NOME.sha256" )
ELENCO=$(docker run --rm --network none -v "$DEST":/out postgres:17 pg_restore --list "/out/$NOME")
echo "File: $DEST/$NOME ($(stat -f %z "$DEST/$NOME") byte), impronta in $NOME.sha256"
echo "Archivio leggibile: voci $(echo "$ELENCO" | grep -c '^[0-9]') | tabelle con dati $(echo "$ELENCO" | grep -c ' TABLE DATA ')"
for t in "auth users" "public profili" "public tesserati" "public adesioni" "public foto" "storage objects" "registrazione richieste"; do
  echo "  dati di ${t/ /.}: $(echo "$ELENCO" | grep -c " TABLE DATA ${t% *} ${t#* } ")"
done
echo "Avvisi di pg_dump: $(grep -c . "$DEST/$NOME.registro" || true) righe (vedi $NOME.registro)"
echo "Fatto. Nessuna modifica alla produzione."
