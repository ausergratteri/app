# App soci Auser Gratteri: come metterla online

Tutto gratuito. Servono circa 30 minuti, meglio da un computer.
Account da usare dappertutto: **ausergratteripa@gmail.com**

## Cosa c'è in questa cartella

| File | A cosa serve |
|---|---|
| `index.html`, `app.js`, `temi.js`, `style.css`, `logo-auser.svg` | L'app vera e propria |
| `config.js` | Il collegamento al database: va compilato (passo 4) |
| `manifest.webmanifest`, `icone/` | Permettono di installarla sul telefono come un'app |
| `supabase/schema.sql` | Crea il database con tutti i permessi dei ruoli (passo 2) |
| `.github/workflows/sveglia.yml` | Tiene attivo il database gratuito (vedi in fondo) |

Finché `config.js` non è compilato, l'app si apre in **modalità prova** con dati di esempio.

---

## 1. Crea il progetto Supabase (il database)

**Organizzazione** (te la chiede la prima volta):
- **Name**: `Auser Gratteri`
- **Type**: *Personal* (o *Non-profit/Other*, se c'è)
- **Plan**: **Free – $0/month**

**Nuovo progetto** (*New project*):
- **Project name**: `auser-gratteri`
- **Database password**: premi *Generate a password*, poi **copiala e conservala** (per esempio nelle note del telefono). All'app non serve, ma può servire in futuro.
- **Region**: scegli **Europe**; se ti fa scegliere la città, **Central EU (Frankfurt)**.
- **Security options**:
  - *Enable Data API* → **acceso** (serve all'app)
  - *Automatically expose new tables and functions* → **spento** (ci pensa il file `schema.sql`)
  - *Enable automatic RLS* (o simile) → **acceso**
- **Advanced configuration** / *Postgres type* / *Compute size*: **lascia tutto com'è** (il predefinito è quello gratuito).
- Premi **Create new project** e aspetta un paio di minuti.

Se trovi un'opzione che non è in questo elenco, lasciala com'è.

## 2. Crea le tabelle

1. Nel menu a sinistra apri **SQL Editor** → *New query*.
2. Apri il file `supabase/schema.sql`, copia **tutto** il contenuto e incollalo.
3. Premi **Run**. Deve comparire "Success".

Se in futuro ricevi una versione nuova di `schema.sql`, puoi rieseguirla allo stesso modo: aggiunge solo quello che manca e non cancella niente.

## 3. Accesso con telefono e PIN

I soci entrano con numero di telefono e un PIN di almeno 6 cifre: nessuna email e nessun SMS.
Per farlo funzionare:

1. Menu **Authentication** → **Sign In / Providers** → **Email**.
2. Disattiva **Confirm email** e salva.

## 4. Collega l'app al database

1. Menu **Project Settings** → **API Keys** (o **Data API**).
2. Copia il **Project URL** e la chiave **Publishable** (se non c'è, quella chiamata **anon public**).
3. Apri `config.js` e incollali al posto delle scritte `INCOLLA_QUI_…`, lasciando le virgolette.

Non usare mai la chiave **secret** o **service_role**: quella non va mai messa nel sito.

## 5. Metti l'app online con GitHub

1. Vai su **github.com** e registrati con ausergratteripa@gmail.com. Scegli un nome utente semplice, per esempio `ausergratteri`.
2. In alto a destra: **+** → *New repository*:
   - Nome: `app`
   - **Public** (serve per la pubblicazione gratuita)
   - *Create repository*
3. Nella pagina del repository: *uploading an existing file* → trascina **tutti** i file e le cartelle di questa cartella → *Commit changes*.
4. La cartella `.github` a volte non viene caricata perché è nascosta. Controlla che ci sia; se manca:
   *Add file* → *Create new file* → come nome scrivi `.github/workflows/sveglia.yml` → incolla il contenuto del file → *Commit changes*.
5. **Settings** → **Pages** → in *Branch* scegli `main` e `/ (root)` → *Save*.
6. Dopo un paio di minuti l'app è online all'indirizzo
   **https://ausergratteri.github.io/app/** (con il tuo nome utente al posto di `ausergratteri`).

## 5b. Caricare i dati iniziali (una volta sola)

1. **SQL Editor → New query**, incolla tutto `supabase/schema.sql` → **Run** (aggiorna il database con l'elenco dei tesserati).
2. **New query**, incolla tutto `supabase/dati_iniziali.sql` → **Run**. Inserisce i 38 tesserati 2026 (solo nome e telefono), le attività dal 2025 a oggi, le due assemblee, alcuni avvisi e gli iscritti scritti nel gruppo WhatsApp. **Non eseguirlo due volte**, altrimenti le attività compaiono doppie.
3. Le locandine stanno nella cartella `locandine/` del sito: caricala su GitHub insieme agli altri file.

**Tesserati.** Chi si registra con il numero di telefono che ha dato all'Auser entra subito come **socio**. Il ruolo di direttivo lo dà sempre il presidente, a mano. In *Gestione → Soci* vedi chi dei tesserati non si è ancora registrato e puoi aggiungere i nuovi tesserati.

**Foto.** Le foto degli eventi sono in `foto_gallerie.zip`, divise per evento. Apri l'evento nell'app, tocca *Aggiungi le tue foto* e seleziona tutte le foto della cartella corrispondente: direttivo e presidente possono caricarne fino a 100 per volta.

## 6. Primo accesso: il presidente

**Il primo che si registra diventa automaticamente presidente.** Quindi, appena l'app è online:

1. Apri l'indirizzo dal telefono.
2. *Primo accesso*: nome, numero e PIN → *Registrati*.
3. Entri come presidente. In **Gestione → Logo, colori e social** carica il logo e i link Facebook e Instagram.

## 7. Direttivo e soci

- Manda il link ai soci (anche nel canale WhatsApp). Ognuno fa *Primo accesso*.
- In **Gestione → Soci** il presidente o il direttivo tocca **Approva**. Prima dell'approvazione chi si registra non vede niente.
- Per i membri del direttivo: il presidente tocca **Nel direttivo**.
- PIN dimenticato: **Gestione → Soci → Nuovo PIN**. Il direttivo può farlo per i soci, il presidente per tutti.
- Chi non ha lo smartphone non serve registrarlo: lo aggiungi a mano tra i partecipanti di ogni gita.

## 8. Temi e gallerie

- **Tema dell'app** (solo il presidente): *Gestione → Tema dell'app*. Ci sono Classico bianco (predefinito), Classico Auser, Natale, Capodanno · 'A Vecchia, Carnevale, Pasqua, Primavera, Estate, Autunno e San Giacomo. Ognuno ha il logo Auser con un accessorio della festa. C'è anche il tema **Automatico**, che cambia da solo con feste e stagioni (San Giacomo dal 24 al 26 luglio e dal 5 al 9 settembre). Tocca un tema per provarlo: lo vedi solo tu finché non premi *Usa questo tema*.
- **Personalizza tutto…**: scegli ogni colore, il carattere dei titoli, la decorazione della testata, gli angoli e la modalità chiara o scura. Se una scelta rende il testo difficile da leggere, l'app te lo segnala.
- **Gallerie**: nella pagina di ogni gita o evento, ogni socio approvato può toccare *Aggiungi le tue foto*, fino a 20 per volta. Le foto vengono rimpicciolite prima dell'invio, così occupano poco. Si trovano in *Bacheca → Gallerie foto* e in Home sotto *Ultime foto*. Chi ha caricato una foto può aggiungere una didascalia o eliminarla; il direttivo può togliere qualsiasi foto.

- **Grandezza del testo**: il tasto **A** in alto a destra passa tra testo normale, grande e molto grande. Ogni socio sceglie la sua.

## 9. Installarla sul telefono

- **iPhone** (Safari): tasto *Condividi* → *Aggiungi alla schermata Home*.
- **Android** (Chrome): menu ⋮ → *Installa app* oppure *Aggiungi a schermata Home*.

---

## Da sapere

- **Pausa del piano gratuito.** Supabase mette in pausa i progetti gratuiti dopo una settimana senza attività. Il file `sveglia.yml` lo tiene attivo con un controllo ogni 3 giorni. Puoi provarlo subito: GitHub → *Actions* → *Sveglia Supabase* → *Run workflow*. Se il progetto andasse comunque in pausa, si riattiva dal pannello Supabase con *Restore*, senza perdere i dati.
- GitHub ferma i controlli automatici se il repository non riceve modifiche per **60 giorni** e manda un'email: basta riattivarli da *Actions*.
- **Copie di sicurezza.** Il piano gratuito non fa backup automatici. Ogni tanto, da Supabase → *Table Editor*, esporta in CSV le tabelle `attivita`, `adesioni` e `profili`.
- **Spazio per le foto.** Il piano gratuito ha 1 GB per i file. Ogni foto ridotta pesa circa 200–400 KB, quindi c'è posto per qualche migliaio di foto.
- **Foto e privacy.** Pubblicando foto di persone, soprattutto di bambini, conviene avere il loro consenso (o quello dei genitori). Aggiungilo all'informativa e chiedi ai soci di pubblicare solo foto in cui le persone sono d'accordo.
- **Privacy.** Nomi e telefoni dei soci sono dati personali: aggiungi all'informativa privacy dell'associazione che vengono usati per l'app e le iscrizioni alle attività. I soci vedono solo la propria iscrizione e il numero dei posti occupati; gli elenchi completi li vedono solo direttivo e presidente.
