// Test comportamentali sull'app VERA (app.js caricato per intero) con un finto Supabase:
// sessioni, logout, cambio utente, URL temporanei delle foto, rinnovo, caricamenti.
const test = require("node:test");
const assert = require("node:assert/strict");
const {avviaApp, cancello, U, BASE} = require("./ambiente-app.js");

const PUBBLICO_GALLERIA = /\/object\/public\/foto\/[^"')]*(1-vecchia|2-privata|3-senza)/;
const firme = app => app.sb.st.richieste.filter(r => r.tipo === "firma");
const fileFinto = (nome = "gita.jpg") => ({name: nome, type: "image/jpeg", size: 1000});

test("socio: le foto delle gallerie si vedono solo con URL temporanei, mai pubblici", async () => {
  const app = await avviaApp({utente: U.soc});
  assert.equal(app.S.realRole, "socio");
  assert.equal(app.S.foto.length, 3);
  for (const f of app.S.foto) assert.match(f.url, /\/object\/sign\//, `foto ${f.id} non firmata`);
  // Ogni foto è firmata nel suo bucket (anche le righe vecchie senza colonna "bucket")
  assert.deepEqual(firme(app).map(r => r.bucket).sort(), ["foto", "foto-private"]);
  assert.ok(app.S.foto.find(f => f.id === "f-priv").url.includes("/sign/foto-private/"));
  // Nell'HTML delle gallerie non compare nessun URL pubblico di una foto di galleria
  app.S.tab = "bacheca"; app.S.bvista = "gallerie"; app.esegui("render()");
  assert.ok(app.html().includes("/object/sign/"), "le gallerie dovrebbero mostrare le foto");
  assert.doesNotMatch(app.html(), PUBBLICO_GALLERIA);
});

test("copertine: URL pubblico del bucket e locandine del sito continuano a funzionare", async () => {
  const app = await avviaApp({utente: U.soc});
  app.S.tab = "home"; app.esegui("render()");
  const html = app.html();
  assert.ok(html.includes(`${BASE}/storage/v1/object/public/foto/${U.pres}/copertina.jpg`), "copertina dal bucket pubblico");
  // Pagina dell'evento con la locandina pubblicata nel sito (cartella locandine/)
  app.esegui('openView("evento", "g-locandina")');
  assert.ok(app.ctx.document.querySelector("#sheet").innerHTML.includes('src="locandine/2026-11-11-san-martino.jpg"'), "locandina dal sito");
  // Le copertine non passano dalla firma
  assert.ok(firme(app).every(r => !r.percorsi.some(p => p.includes("copertina"))));
});

test("chi è in attesa e chi non è entrato non chiedono firme né vedono foto", async () => {
  const attesa = await avviaApp({utente: U.att});
  assert.equal(attesa.S.realRole, "lettore");
  assert.equal(attesa.S.foto.length, 0);
  assert.equal(firme(attesa).length, 0);
  const anonimo = await avviaApp();
  assert.equal(anonimo.S.foto.length, 0);
  assert.equal(firme(anonimo).length, 0);
});

test("Storage non risponde: nessuna foto (nessun ripiego sugli URL pubblici) e avviso chiaro", async () => {
  const app = await avviaApp({utente: U.soc, dati: undefined});
  app.sb.st.firmaRotta = true;
  app.S._fotoFirmateAlle = 0;
  await app.esegui("carica()");
  assert.equal(app.S.foto.length, 0);
  assert.equal(app.S.fotoErrore, true);
  app.S.tab = "bacheca"; app.S.bvista = "gallerie"; app.esegui("render()");
  assert.match(app.html(), /Le foto non sono visibili in questo momento/);
  assert.doesNotMatch(app.html(), PUBBLICO_GALLERIA);
});

test("una sola foto non firmabile (file mancante) non nasconde le altre", async () => {
  const app = await avviaApp({utente: U.soc});
  app.sb.st.firmaMancante.add(`${U.soc}/1-vecchia.jpg`);
  app.S._fotoFirmateAlle = 0;
  await app.esegui("carica()");
  assert.deepEqual(Array.from(app.S.foto, f => f.id).sort(), ["f-priv", "f-senza"]);
  assert.equal(app.S.fotoScartate, 1);
  assert.equal(app.S.fotoErrore, false);
});

test("logout mentre i dati stanno arrivando: nessun dato della sessione chiusa resta o ricompare", async () => {
  const app = await avviaApp({utente: U.pres});
  assert.ok(app.S.tesserati.length > 0);
  const c = cancello();
  app.sb.st.pausa = c.p;
  const inCorso = app.esegui("carica()");
  await app.sb.comandi.esci();
  c.apri(); app.sb.st.pausa = null;
  await inCorso;
  await app.calma();
  assert.equal(app.S.realRole, "lettore");
  assert.equal(app.S.myId, null);
  assert.equal(app.S.foto.length, 0);
  assert.equal(app.S.tesserati.length, 0);
  assert.equal(app.S.profili.length, 0);
  assert.equal(Object.keys(app.S.att).length, 0);
  assert.doesNotMatch(app.html(), /Tesserata Finta|\/object\/sign\//);
});

test("logout mentre si rinnovano gli URL: le foto non ricompaiono", async () => {
  const app = await avviaApp({utente: U.soc});
  app.S._fotoFirmateAlle = Date.now() - 46 * 60000;
  const c = cancello();
  app.sb.st.pausaFirma = c.p;
  const rinnovo = app.esegui("rinnovaFoto()");
  await app.sb.comandi.esci();
  c.apri(); app.sb.st.pausaFirma = null;
  await rinnovo;
  assert.equal(app.S.foto.length, 0);
  assert.equal(app.S.realRole, "lettore");
});

test("cambio utente senza logout (presidente → socio): spariti subito i dati riservati", async () => {
  const app = await avviaApp({utente: U.pres});
  app.esegui("IMP = {file: 'prova.xls', esito: {}}");  // anteprima di un'importazione aperta
  assert.ok(app.S.tesserati.length > 0);
  const c = cancello();
  app.sb.st.pausaProfilo = c.p;
  app.sb.comandi.entra(U.soc);
  // Prima ancora che arrivi il profilo del nuovo utente: niente dati del presidente
  assert.equal(app.S.tesserati.length, 0);
  assert.equal(app.S.realRole, "lettore");
  assert.equal(app.esegui("IMP"), null);
  c.apri(); app.sb.st.pausaProfilo = null;
  await app.attendi(() => app.S.realRole === "socio");
  await app.calma();
  assert.equal(app.S.tesserati.length, 0, "il socio non vede i tesserati");
  assert.equal(app.S.profili.length, 0, "il socio non vede l'elenco dei profili");
});

test("profilo che arriva in ritardo dopo un cambio utente non assegna il ruolo sbagliato", async () => {
  const app = await avviaApp();
  const lento = cancello();
  app.sb.st.pausaProfilo = lento.p;
  app.sb.comandi.entra(U.pres);           // la lettura del profilo del presidente resta in sospeso
  await new Promise(r => setTimeout(r, 15));
  app.sb.st.pausaProfilo = null;
  app.sb.comandi.entra(U.soc);            // intanto entra il socio
  await app.attendi(() => app.S.realRole === "socio");
  lento.apri();                           // arriva la vecchia risposta del presidente
  await app.calma();
  assert.equal(app.S.realRole, "socio");
  assert.equal(app.S.myId, U.soc);
  assert.equal(app.S.tesserati.length, 0);
});

test("due caricamenti simultanei: vince l'ultimo, quello più vecchio viene scartato", async () => {
  const app = await avviaApp({utente: U.soc});
  const c = cancello();
  app.sb.st.pausa = c.p;
  const primo = app.esegui("carica()");     // vede i dati di prima, ma arriva tardi
  app.sb.st.pausa = null;
  app.sb.st.tabelle.attivita[0].titolo = "Titolo aggiornato";
  await app.esegui("carica()");
  c.apri();
  await primo;
  assert.equal(app.S.att["g-futura"].titolo, "Titolo aggiornato");
});

test("rinnovo: dopo 45 minuti tutti gli URL vengono rifirmati", async () => {
  const app = await avviaApp({utente: U.soc});
  const prima = app.S.foto.map(f => f.url);
  app.S._fotoFirmateAlle = Date.now() - 46 * 60000;
  await app.esegui("rinnovaFoto()");
  const dopo = app.S.foto.map(f => f.url);
  assert.equal(dopo.length, 3);
  dopo.forEach((u, i) => { assert.notEqual(u, prima[i]); assert.match(u, /\/object\/sign\//); });
  assert.ok(Date.now() - app.S._fotoFirmateAlle < 5000);
  // Il timer dell'app controlla ogni minuto
  assert.ok(app.intervalli.some(t => t.ms === 60000));
});

test("rinnovo: prima dei 45 minuti non fa richieste", async () => {
  const app = await avviaApp({utente: U.soc});
  const n = firme(app).length;
  await app.esegui("rinnovaFoto()");
  assert.equal(firme(app).length, n);
});

test("salvataggi frequenti: le foto già firmate non si rifirmano (restano nella cache del telefono)", async () => {
  const app = await avviaApp({utente: U.soc});
  const prima = app.S.foto.map(f => f.url);
  const n = firme(app).length;
  await app.esegui("carica()");
  assert.equal(firme(app).length, n, "nessuna nuova firma");
  assert.deepEqual(app.S.foto.map(f => f.url), prima);
  // Una foto nuova invece si firma, solo lei
  app.sb.st.tabelle.foto.push({id: "f-nuova", attivita_id: "g-passata", user_id: U.soc, percorso: `${U.soc}/9-nuova.jpg`, bucket: "foto-private", url: ""});
  app.sb.st.oggetti["foto-private"].add(`${U.soc}/9-nuova.jpg`);
  await app.esegui("carica()");
  const nuove = firme(app).slice(n);
  assert.deepEqual(nuove.flatMap(r => r.percorsi), [`${U.soc}/9-nuova.jpg`]);
  assert.equal(app.S.foto.length, 4);
});

test("rinnovo fallito: dopo 55 minuti le foto spariscono, poi tornano quando Storage risponde", async () => {
  const app = await avviaApp({utente: U.soc});
  app.sb.st.firmaRotta = true;
  app.S._fotoFirmateAlle = Date.now() - 50 * 60000;
  await app.esegui("rinnovaFoto()");
  assert.equal(app.S.foto.length, 3, "a 50 minuti gli URL valgono ancora");
  app.S._fotoFirmateAlle = Date.now() - 56 * 60000;
  await app.esegui("rinnovaFoto()");
  assert.equal(app.S.foto.length, 0);
  assert.equal(app.S.fotoErrore, true);
  app.sb.st.firmaRotta = false;
  await app.esegui("rinnovaFoto()");     // nuovo tentativo al minuto successivo
  assert.equal(app.S.foto.length, 3);
  assert.equal(app.S.fotoErrore, false);
});

test("caricamento: le foto delle gallerie vanno nel bucket privato, senza URL pubblico", async () => {
  const app = await avviaApp({utente: U.soc});
  app.esegui("S.dichiaraFoto = true");
  await app.esegui(`caricaFoto("g-passata", [${JSON.stringify(fileFinto())}])`);
  const up = app.sb.st.richieste.filter(r => r.tipo === "upload");
  assert.equal(up.length, 1);
  assert.equal(up[0].bucket, "foto-private");
  assert.ok(up[0].percorso.startsWith(U.soc + "/"));
  assert.equal(up[0].opz.upsert, false);
  const riga = app.sb.st.tabelle.foto.at(-1);
  assert.equal(riga.bucket, "foto-private");
  assert.equal(riga.url, "");
  assert.equal(riga.user_id, U.soc);
  assert.ok(!app.sb.st.richieste.some(r => r.tipo === "publicUrl" && r.bucket === "foto-private"));
  // Dopo il caricamento la nuova foto si vede, firmata
  assert.ok(app.S.foto.some(f => f.percorso === riga.percorso && /\/sign\/foto-private\//.test(f.url)));
});

test("caricamento: se la riga non si salva, il file appena caricato viene tolto", async () => {
  const app = await avviaApp({utente: U.soc});
  app.sb.st.inserimentoRotto = true;
  app.esegui("S.dichiaraFoto = true");
  await app.esegui(`caricaFoto("g-passata", [${JSON.stringify(fileFinto())}])`);
  const up = app.sb.st.richieste.find(r => r.tipo === "upload");
  const rm = app.sb.st.richieste.find(r => r.tipo === "remove");
  assert.ok(rm, "il file orfano deve essere tolto");
  assert.equal(rm.bucket, "foto-private");
  assert.deepEqual(Array.from(rm.percorsi), [up.percorso]);
  assert.equal(app.sb.st.oggetti["foto-private"].has(up.percorso), false);
});

test("caricamento di più foto: se si esce a metà, le altre non vengono caricate", async () => {
  const app = await avviaApp({utente: U.soc});
  const c = cancello();
  const originale = app.sb.client.storage.from;
  let n = 0;
  app.sb.client.storage.from = b => {
    const x = originale(b);
    const up = x.upload;
    x.upload = async (...a) => { const r = await up(...a); if (++n === 1) await c.p; return r; };
    return x;
  };
  const tre = JSON.stringify([fileFinto("a.jpg"), fileFinto("b.jpg"), fileFinto("c.jpg")]);
  app.esegui("S.dichiaraFoto = true");
  const carica = app.esegui(`caricaFoto("g-passata", ${tre})`);
  await new Promise(r => setTimeout(r, 10));
  await app.sb.comandi.esci();
  c.apri();
  await carica;
  assert.equal(app.sb.st.richieste.filter(r => r.tipo === "upload").length, 1);
  assert.equal(app.S.foto.length, 0);
});

test("copertine, bacheca e logo: restano nel bucket pubblico con URL pubblico", async () => {
  const app = await avviaApp({utente: U.pres});
  const url = await app.esegui(`api.foto(${JSON.stringify(fileFinto("copertina2.jpg"))})`);
  const up = app.sb.st.richieste.filter(r => r.tipo === "upload").at(-1);
  assert.equal(up.bucket, "foto");
  assert.ok(url.startsWith(`${BASE}/storage/v1/object/public/foto/${U.pres}/`));
});

test("eliminazione: il file si toglie dal bucket in cui sta davvero", async () => {
  const app = await avviaApp({utente: U.soc});
  await app.esegui(`(async () => {
    const f1 = S.foto.find(x => x.id === "f-priv"), f2 = S.foto.find(x => x.id === "f-pub");
    await api.togliFile(f1.percorso, bucketFoto(f1));
    await api.togliFile(f2.percorso, bucketFoto(f2));
  })()`);
  const rm = app.sb.st.richieste.filter(r => r.tipo === "remove");
  assert.deepEqual(rm.map(r => r.bucket), ["foto-private", "foto"]);
});
