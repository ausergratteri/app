#!/usr/bin/env bash
# =====================================================================
#  Deploy della SOLA Edge Function "registrazione" sul progetto Supabase di PRODUZIONE.
#  Da eseguire SOLO dall'amministratore, nel proprio Terminale, dopo l'autorizzazione esplicita.
#  - Progetto: SOLO l'identificativo di produzione (impronta SHA-256 fissata qui sotto, uguale a
#    config.js della cartella e di origin/main).
#  - File: index.ts e logica.ts presi dal COMMIT indicato (git archive in una cartella temporanea
#    pulita, senza collegamenti a progetti), mai dall'albero di lavoro.
#  - Token di accesso: lettura nascosta, solo in questo processo; revocarlo dopo l'uso.
#  - Verifica JWT disattivata (--no-verify-jwt): la funzione controlla origine, limiti e dati da sé.
#  NON tocca il database, i segreti o l'app. I segreti della funzione si impostano nel pannello (passo R3).
# =====================================================================
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$HOME/Progetti/auser-otp-prova-locale/.cli/node_modules/.bin/supabase"
COMMIT="${1:?Indicare il commit da pubblicare (es. quello del rilascio)}"
IMPRONTA_PROD="01f443419b5baf940aa39c7a7fcad19176ad0f741469ab76913e8a967484cec2"
stop() { echo "STOP: $*" >&2; exit 1; }

git -C "$REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null || stop "commit $COMMIT inesistente"
# 1. Progetto di produzione
REF=$(sed -nE 's#.*url: "https://([a-z0-9]{20})\.supabase\.co".*#\1#p' "$REPO/config.js" | head -1)
REF_MAIN=$(git -C "$REPO" show origin/main:config.js | sed -nE 's#.*url: "https://([a-z0-9]{20})\.supabase\.co".*#\1#p' | head -1)
REF_COMMIT=$(git -C "$REPO" show "$COMMIT:config.js" | sed -nE 's#.*url: "https://([a-z0-9]{20})\.supabase\.co".*#\1#p' | head -1)
[ "${#REF}" -eq 20 ] && [ "$REF" = "$REF_MAIN" ] && [ "$REF" = "$REF_COMMIT" ] || stop "config.js, origin/main e il commit non indicano lo stesso progetto"
[ "$(printf '%s' "$REF" | shasum -a 256 | cut -d' ' -f1)" = "$IMPRONTA_PROD" ] || stop "identificativo diverso da quello della produzione"

# 2. File della funzione dal commit, in una cartella temporanea pulita
TMP=$(mktemp -d); chmod 700 "$TMP"; trap 'rm -rf "$TMP"; unset SUPABASE_ACCESS_TOKEN' EXIT
git -C "$REPO" archive "$COMMIT" supabase/functions/registrazione/index.ts supabase/functions/registrazione/logica.ts | tar -x -C "$TMP"
for f in index.ts logica.ts; do [ -s "$TMP/supabase/functions/registrazione/$f" ] || stop "$f mancante nel commit"; done
echo "Funzione dal commit $COMMIT: index.ts $(shasum -a 256 "$TMP/supabase/functions/registrazione/index.ts" | cut -c1-16), logica.ts $(shasum -a 256 "$TMP/supabase/functions/registrazione/logica.ts" | cut -c1-16)"
[ -x "$CLI" ] || stop "CLI non trovata"

# 3. Token: lettura nascosta, formato controllato, solo in questo processo
read -r -s -p "Token di accesso Supabase (non viene mostrato): " SUPABASE_ACCESS_TOKEN; echo
[[ "$SUPABASE_ACCESS_TOKEN" =~ ^sbp_[A-Za-z0-9_]{20,}$ ]] || stop "formato del token non riconosciuto"
export SUPABASE_ACCESS_TOKEN

# 4. Conferma esplicita e deploy (nessun --prune, nessun collegamento permanente)
echo "Pubblico SOLO la funzione 'registrazione' sul progetto di PRODUZIONE ${REF:0:4}… (verifica JWT disattivata)."
read -r -p "Scrivi PRODUZIONE per confermare: " CONFERMA
[ "$CONFERMA" = "PRODUZIONE" ] || stop "annullato"
DO_NOT_TRACK=1 SUPABASE_TELEMETRY_DISABLED=1 SUPABASE_HOME="$TMP/.supabase-home" \
  "$CLI" functions deploy registrazione --remote="$REF" --workdir "$TMP" \
  --no-verify-jwt --use-api --agent no
echo "Fatto. Revoca il token dal pannello di Supabase (Account → Access Tokens)."
