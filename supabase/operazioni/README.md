# Operazioni per le migrazioni 20261118 (sicurezza), 20261119 (importazione tesserati) e 20261120 (foto private)

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

## Impronte attese delle funzioni (controllo "FOTOGRAFIA DELLA STRUTTURA")

`left(md5(prosrc), 8)` dopo le tre migrazioni:

| Funzione | Impronta |
|---|---|
| acc_valido | 4cdf8da2 |
| conteggi | 67696af9 |
| controlla_adesione | dc51d1e8 (controllo dei posti corretto, già con la sola 20261118) |
| controlla_foto | 5e2884a0 dopo 20261118, 4fc9e77e dopo 20261120 |
| controlla_ruolo | cdb7ca58 |
| importa_tesserati | 36f1f714 |
| nuovo_profilo | d08f0d69 |
| reimposta_pin | bf88cbc1 |
| livello / pulisci_adesioni / solo_cifre_tel / sveglia | invariate (1d5541a5 / c7966924 / 2dcd1ade / ccea2d8b) |
