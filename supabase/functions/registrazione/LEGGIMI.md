# Funzione server "registrazione" (codice OTP via e-mail)

Gestisce il "Primo accesso" dell'app: manda un codice di 6 cifre all'e-mail che l'associazione
ha nell'elenco dei tesserati, lo verifica e solo dopo crea l'account da socio con il PIN scelto.
Senza e-mail in elenco crea un account "in attesa" che il direttivo approva.

| File | Cosa fa |
|---|---|
| `logica.ts` | Tutte le regole (nessuna dipendenza esterna: la provano i test in `test/`) |
| `index.ts` | Collega la logica a Supabase (chiave secret), a Gmail (SMTP 465) e ai segreti |
| `../../migrations/20261123_registrazione_otp.sql` | Tabella privata delle richieste, funzioni SQL, nuovo `nuovo_profilo()` |

## Segreti (Supabase → Edge Functions → Secrets)

Non vanno MAI nel repository, nel frontend, in chat o nei report.

| Nome | Valore |
|---|---|
| `REGISTRAZIONE_PEPE` | 48 caratteri casuali (es. `openssl rand -base64 36` nel proprio Terminale) |
| `GMAIL_UTENTE` | l'indirizzo Gmail dell'associazione (mittente) |
| `GMAIL_PASSWORD_APP` | una *password per le app* di Google (16 caratteri), NON la password dell'account |
| `EMAIL_CONSENTITE` | durante le prove: SOLO il proprio indirizzo. Si toglie per aprire a tutti |
| `ORIGINE_CONSENTITA` | `https://ausergratteri.github.io` (predefinito) |

`SUPABASE_URL` e la chiave secret li fornisce Supabase alla funzione.

## Gmail

1. Account Google dell'associazione → **Sicurezza** → attivare la **Verifica in due passaggi**.
2. **Password per le app** → nome "AUSER app" → copiare i 16 caratteri direttamente nel segreto
   `GMAIL_PASSWORD_APP` (senza salvarli altrove). Si può revocare in qualsiasi momento.
3. Limiti di Gmail: circa 500 messaggi al giorno; ben oltre il bisogno (pochi soci al giorno).
4. Da verificare alla prima prova reale: che le Edge Functions di Supabase possano aprire
   connessioni SMTP verso `smtp.gmail.com:465`. Se non possono, l'alternativa è un servizio
   via HTTPS (es. Brevo, gratuito fino a 300 e-mail al giorno): cambia solo `inviaEmail` in `index.ts`.

## Supabase Auth

* **Allow new users to sign up: disattivato** (consigliato). Così nessuno crea account con le API
  pubbliche di Auth: li crea solo questa funzione. Anche se restasse attivo, il database non dà
  mai il ruolo socio senza la prova OTP (`nuovo_profilo()`), quindi l'OTP non si aggira.
* **Confirm email: disattivato** (come oggi: gli indirizzi di accesso sono interni, non e-mail vere).
* Lunghezza minima password: 6 (il PIN va da 6 a 12 cifre).

## Pubblicazione (solo con autorizzazione)

```bash
supabase link --project-ref <ref-del-progetto>
supabase functions deploy registrazione --no-verify-jwt
```

`--no-verify-jwt` serve perché la chiamano persone non ancora registrate: i controlli sono nella
logica (limiti, codici, gettoni) e nel database (solo `service_role` esegue le funzioni).

## Prova con la propria e-mail (senza scrivere ad altri soci)

1. `EMAIL_CONSENTITE` = solo il proprio indirizzo.
2. Nell'elenco dei tesserati: una voce di prova con un numero **mai registrato** e il proprio indirizzo
   (oppure, se si è già nell'elenco, controllare che il proprio indirizzo sia giusto).
3. *Primo accesso* con nome, cognome e quel numero → arriva il codice → PIN → socio.
4. Prove negative: codice sbagliato, codice scaduto (attendere 10 minuti), secondo uso del codice,
   numero non in elenco (stessa schermata, nessuna e-mail).
5. Alla fine: togliere la voce di prova e il suo account (con autorizzazione), poi togliere
   `EMAIL_CONSENTITE` per aprire a tutti.

## Registri

La funzione scrive solo eventi senza dati personali (`avvio`, `verifica`, `completa`, `invio_riuscito`...):
mai codici, gettoni, PIN, e-mail, telefoni o indirizzi IP.
