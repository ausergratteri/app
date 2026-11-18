# Operazioni per le migrazioni 20261118 (sicurezza) e 20261119 (importazione tesserati)

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
