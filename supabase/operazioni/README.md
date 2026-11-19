# Operazioni per le migrazioni 20261118 (sicurezza), 20261119 (importazione tesserati), 20261120 (foto private), 20261121 (permessi sulle foto) e 20261122 (correzioni del retest)

Riepilogo completo degli interventi, dello stato della produzione e dei rischi residui:
[`SICUREZZA_INTERVENTI_2026.md`](../../SICUREZZA_INTERVENTI_2026.md).

Script da incollare nel SQL Editor di Supabase, **in questo ordine**. Non contengono
credenziali né dati: leggono e copiano solo quello che è già nel database.

| Passo | File | Cosa fa | Modifica dati? |
|---|---|---|---|
| 1 | `01_controlli_preliminari.sql` | Elenca i dati che le migrazioni bloccherebbero o cambierebbero | No, solo lettura |
| 2 | `02_backup.sql` | Copia tabelle, funzioni, regole e trigger nello schema `backup_20261118` | Crea solo le copie |
| 3 | `../migrations/20261118_sicurezza_accessi.sql` | Applica le correzioni di sicurezza | Sì |
| 4 | `../migrations/20261119_importa_tesserati.sql` | Aggiunge email e numero tessera, importazione e registro | Sì (solo colonne nuove) |
| — | `03_rollback.sql` | Solo in caso di problemi: torna alle regole di sicurezza di prima | Sì |
| — | `04_rollback_importazione.sql` | Solo in caso di problemi: toglie l'importazione (va eseguito prima di `03`) | Sì |

Prima del passo 3 il controllo **05** deve dire `ok`: un link social senza `https://`
impedirebbe al presidente di salvare le impostazioni, anche il tema.
Prima del passo 4 il controllo **12** deve dire `ok`: due tesserati con lo stesso telefono
fermano la migrazione (che in quel caso non cambia nulla).

Il risultato dei controlli mostra nomi e numeri dei soci: non condividerlo fuori dal direttivo.
Lo schema `backup_20261118` contiene una copia dei dati personali: quando non serve più,
eliminarlo con `drop schema backup_20261118 cascade;`.

## Foto delle gallerie nel bucket privato (20261120)

Le 204 foto delle gallerie passano dal bucket pubblico `foto` al bucket privato
`foto-private`. Copertine, immagini della bacheca e logo restano nel bucket pubblico.
Le copertine in `locandine/` sono file del sito (GitHub Pages) e non sono coinvolte.
Nessun passo cancella file finché non lo si chiede esplicitamente all'ultimo passo.

| Passo | Cosa | Dove | Modifica? | Come tornare indietro |
|---|---|---|---|---|
| F1 | `../migrations/20261120_foto_private.sql` | SQL Editor | Crea il bucket privato, le sue regole e la colonna `foto.bucket` (tutte le righe restano `foto`) | Parte C di `05_rollback_foto_private.sql` |
| F2 | Pubblicare la nuova app (`app.js`, `sicurezza.js`, `index.html`) | GitHub Pages | Le foto si vedono con URL temporanei; le nuove foto vanno nel bucket privato | Ripubblicare la versione precedente (vedi nota) |
| F3 | `node foto-private.js piano` | Terminale | No, solo lettura | — |
| F4 | `node foto-private.js copia --uscita DIR` | Terminale | Copia i file nel bucket privato e li verifica (SHA-256). Il pubblico non cambia | Nessun effetto per l'app; le copie private si possono lasciare |
| F5 | `06_attiva_foto_private.sql` | SQL Editor | Passa al bucket privato solo le righe con copia identica (dimensione + eTag). Salva lo stato in `backup_20261120` | `05_rollback_foto_private.sql` (Parte A) |
| F6 | Prove con i 3 account di prova e `node foto-private.js verifica` | App + Terminale | No | — |
| F7 | Dopo almeno 2–4 settimane senza problemi: `node foto-private.js elimina-pubbliche --conferma ELIMINA-COPIE-PUBBLICHE` | Terminale | **Toglie le copie pubbliche** (solo quelle con copia privata identica, mai copertine/bacheca/logo) | `node foto-private.js riporta-pubbliche` |

Note:
* **Ordine**: F2 prima di F5. La nuova app funziona anche con le foto ancora nel bucket
  pubblico; la vecchia app invece non mostra le foto attivate (usa gli URL pubblici).
* Prima di tornare alla vecchia app dopo F5: `05_rollback_foto_private.sql` (Parte A) e, se
  dopo F2 sono state caricate nuove foto, `riporta-pubbliche` + Parte B.
* La chiave secret (service role) si inserisce solo nel proprio Terminale con `read -s`
  (istruzioni in testa a `foto-private.js`) e poi si toglie con `unset`. Mai in chat o in file.
* Il registro CSV di ogni comando contiene solo id e percorsi tecnici: tenerlo comunque nel
  disco cifrato. Lo schema `backup_20261120` contiene gli URL pubblici di prima: eliminarlo
  (`drop schema backup_20261120 cascade;`) dopo F7.
* Rollback della sicurezza (`03_rollback.sql`) dopo F1: prima `05_rollback_foto_private.sql`.

## Permessi sulle foto per ruolo (20261121)

Presidente e direttivo vedono e cancellano tutte le foto; il socio le vede e cancella
solo le sue; chi è in attesa, espulso (riportato in attesa) o senza profilo non vede,
non carica, non modifica e non cancella nulla. Non tocca file né righe: solo regole.

| Passo | File | Cosa fa | Modifica? |
|---|---|---|---|
| P1 | `07_controlla_policy_foto.sql` | Elenca le regole su `public.foto` e `storage.objects`; quelle con `atteso = NO` sono regole concorrenti da esaminare | No, solo lettura |
| P2 | `../migrations/20261121_permessi_foto_ruoli.sql` | Corregge le regole "le proprie foto" e aggiunge regole restrittive. Si ferma senza cambiare nulla se trova regole sconosciute | Sì (solo regole) |
| P3 | `07_controlla_policy_foto.sql` | Di nuovo: 4 restrittive per tabella, nessuna riga `NO`, conteggi delle foto invariati | No |
| P4 | Prove con i 3 account di prova (socio: vede, cancella solo le sue; direttivo/presidente: cancellano tutte) | App | Sì, solo foto di prova |
| — | `08_rollback_permessi_foto.sql` | Solo in caso di problemi: regole identiche a quelle dopo 20261120 | Sì (solo regole) |

## Correzioni del retest Strix (20261122)

Dal retest Strix del 19/11/2026 (report conservato solo in locale, in `strix_runs/`):
adesioni di chi è stato riportato "in attesa", tema non valido che blocca l'app,
SVG nel bucket pubblico. Non tocca file né dati: solo regole, un vincolo e i tipi
ammessi dal bucket `foto`. Insieme va pubblicata la nuova app (`app.js`, `temi.js`,
`importa-xls.js`, `index.html`): rifiuta gli SVG, ignora temi e nomi "ereditati"
(`constructor`...), limita e-mail (254 caratteri) e colonne (100) nell'importazione.

| Passo | File | Cosa fa | Modifica? |
|---|---|---|---|
| R1 | `10_controlla_svg.sql` | Tipi ammessi dai bucket, SVG già presenti in `foto` e dove sono usati, tema attuale | No, solo lettura |
| R2 | `../migrations/20261122_correzioni_retest.sql` | Regole delle adesioni per ruolo (+2 restrittive), vincolo sul tema, `foto` senza SVG. Si ferma se trova regole sconosciute sulle adesioni | Sì (regole, vincolo, tipi del bucket) |
| R3 | `10_controlla_svg.sql` e `07_controlla_policy_foto.sql` | Controllo dopo: nessun SVG ammesso, regole delle foto invariate | No |
| R4 | Pubblicare la nuova app | GitHub Pages | Sì |
| R5 | Prove con gli account di prova: socio vede/modifica/annulla solo le sue iscrizioni; direttivo tutte; account in attesa nessuna; caricare un PNG funziona, un SVG viene rifiutato | App | Solo dati di prova |
| — | `11_rollback_correzioni_retest.sql` | Solo in caso di problemi: regole, vincolo e tipi del bucket come dopo 20261121 | Sì |

Note:
* Gli SVG già presenti nel bucket `foto` non vengono toccati: se uno è il logo, caricare
  prima un logo PNG dall'app; gli altri si valutano a mano (dopo averne salvato una copia).
* Se il tema salvato non è valido, la migrazione lo segnala e il vincolo vale solo per le
  nuove scritture: correggere il tema e poi `validate constraint` (comando nel messaggio).
* Nessuna funzione cambia: le impronte qui sotto restano valide.

## Registrazione con codice via e-mail (20261123) – NON ancora in produzione

Risolve la registrazione "al posto di un tesserato" (vuln-0001). Dettagli, segreti, Gmail e
pubblicazione della funzione server: `../functions/registrazione/LEGGIMI.md`.

| Passo | Cosa | Dove | Modifica? |
|---|---|---|---|
| O1 | `13_controlla_registrazione.sql`: quanti tesserati hanno l'e-mail, e-mail condivise, ecc. (solo numeri) | SQL Editor | No |
| O2 | Password per le app di Gmail e segreti della funzione (con `EMAIL_CONSENTITE` = solo la propria e-mail) | Google + Supabase | Sì (configurazione) |
| O3 | `../migrations/20261123_registrazione_otp.sql` | SQL Editor | Sì (funzioni, tabella privata, `nuovo_profilo`) |
| O3b | `../migrations/20261124_minimo_privilegio_tabelle.sql`: toglie ad anon e authenticated TRUNCATE, REFERENCES e TRIGGER sulle tabelle dell'app (anche per le tabelle future) | SQL Editor | Sì (solo permessi) |
| O4 | `supabase functions deploy registrazione --no-verify-jwt` | Terminale | Sì |
| O5 | Pubblicare la nuova app (`app.js`, `index.html`) | GitHub Pages | Sì |
| O6 | Prova con la propria e-mail (vedi la guida della funzione) | App | Solo dati di prova |
| O7 | Supabase Auth: **Allow new users to sign up** disattivato | Pannello | Sì (impostazione) |
| O8 | Togliere `EMAIL_CONSENTITE` (apertura a tutti i soci) | Supabase | Sì |
| — | `12_rollback_registrazione_otp.sql` + app precedente + riattivare le iscrizioni pubbliche | | Sì |

Note:
* **Prima di O3**: in un progetto di prova in cloud verificare che la migrazione possa cancellare da
  `auth.users` (sostituzione di un account "in attesa" senza dati) e misurare il tempo tra
  prenotazione e conferma (finestra di 2 minuti). Finché non è verificato, non eseguire in produzione.
* Ordine importante: O3 prima di O5 (la nuova app usa la funzione server), O4 prima di O5.
  Tra O3 e O5 la vecchia app continua a registrare, ma i nuovi account restano "in attesa"
  (il direttivo li approva): nessuno viene bloccato e nessuno entra senza verifica.
* Gli account esistenti, i PIN e i ruoli non cambiano. L'accesso con telefono e PIN resta uguale.

## Impronte attese delle funzioni (controllo "FOTOGRAFIA DELLA STRUTTURA")

`left(md5(prosrc), 8)` dopo le migrazioni (20261121 non cambia funzioni):

| Funzione | Impronta |
|---|---|
| acc_valido | 4cdf8da2 |
| conteggi | 67696af9 |
| controlla_adesione | dc51d1e8 (controllo dei posti corretto, già con la sola 20261118) |
| controlla_foto | 5e2884a0 dopo 20261118, 4fc9e77e dopo 20261120 |
| controlla_ruolo | cdb7ca58 |
| importa_tesserati | 36f1f714 |
| nuovo_profilo | d08f0d69 fino a 20261122; **3adac188** dopo 20261123 |
| reimposta_pin | bf88cbc1 |
| livello / pulisci_adesioni / solo_cifre_tel / sveglia | invariate (1d5541a5 / c7966924 / 2dcd1ade / ccea2d8b) |
| registrazione_avvia / _verifica / _prenota / _elimina_attesa / _conferma / _manuale_consentita (dopo 20261123) | 6b704981 / 771510cd / da45f1c3 / 296211bf / 91b3efca / cf293dc3 |
| registrazione.ha_dati / parole / nomi_corrispondono (dopo 20261123) | 77b8b175 / 4d146bf2 / 26bd802d |
