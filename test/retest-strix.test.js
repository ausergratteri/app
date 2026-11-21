// Test di regressione per le correzioni del retest Strix (19/11/2026), sull'app VERA
// caricata con il finto Supabase di ambiente-app.js. Nessuna rete.
//  - vuln-0005: nome partecipante "constructor" bloccava la scheda attività
//  - vuln-0006: impostazioni.tema "constructor" bloccava l'avvio dell'app
//  - vuln-0002: niente SVG caricati (bucket pubblico)
//  - vuln-0003 / vuln-0004: e-mail lunghissime e fogli Excel larghissimi
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {avviaApp, datiProva, U} = require("./ambiente-app.js");
const I = require("../importa-xls.js");

const NOMI_EREDITATI = ["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf"];
const radice = path.join(__dirname, "..");

// ---------- Tema ----------
for (const tema of NOMI_EREDITATI) {
  test(`tema "${tema}" salvato nel database: l'app parte comunque con il tema base`, async () => {
    const dati = datiProva();
    dati.tabelle.impostazioni[0].tema = tema;
    const app = await avviaApp({utente: U.soc, dati});
    assert.deepEqual(app.errori, [], "nessun errore all'avvio");
    assert.equal(app.S.realRole, "socio");
    assert.ok(app.html().length > 0, "l'app ha disegnato la pagina");
    assert.equal(app.esegui(`temaDa({tema: ${JSON.stringify(tema)}}) === TEMI[TEMA_BASE]`), true);
    assert.equal(app.esegui(`temaPer(${JSON.stringify(tema)}) === TEMI[TEMA_BASE]`), true);
    app.S.temaScelto = tema;
    assert.equal(app.esegui("nomeAnteprima()"), "un nuovo tema");
  });
}

test("anche senza accesso (pagina di ingresso) un tema ereditato non blocca l'app", async () => {
  const dati = datiProva();
  dati.tabelle.impostazioni[0].tema = "constructor";
  const app = await avviaApp({utente: null, dati});
  assert.deepEqual(app.errori, []);
  assert.ok(app.html().length > 0);
});

test("i temi validi funzionano come prima (esistenti, personalizzato, automatico)", async () => {
  const app = await avviaApp({utente: U.soc});
  assert.equal(app.esegui('temaDa({tema: "natale"}) === TEMI.natale'), true);
  assert.equal(app.esegui('temaDa({}) === TEMI[TEMA_BASE]'), true);
  assert.equal(app.esegui('temaDa({tema: "personalizzato", tema_personalizzato: {top1: "#112233"}}).top'), "#112233");
  assert.ok(app.esegui('Object.keys(TEMI).includes(temaDelGiorno()) && temaDa({tema: "automatico"}) === TEMI[temaDelGiorno()]'));
});

test("tema personalizzato con carattere/decorazione/logo ereditati: si usano i valori predefiniti", async () => {
  const app = await avviaApp({utente: U.soc});
  for (const k of NOMI_EREDITATI) {
    const t = app.esegui(`daPersonalizzato({font: ${JSON.stringify(k)}, decor: ${JSON.stringify(k)}, logo: ${JSON.stringify(k)}})`);
    assert.notEqual(t.font, k); assert.equal(t.decor, "cerchi"); assert.equal(t.logo, "");
    const svg = app.esegui(`logoSvg({logo: ${JSON.stringify(k)}})`);
    assert.doesNotMatch(svg, /function|native code/, "nessun testo di funzione dentro il logo");
  }
  // I valori validi restano
  const ok = app.esegui('daPersonalizzato({decor: "auser", logo: "natale"})');
  assert.equal(ok.decor, "auser"); assert.equal(ok.logo, "natale");
});

test("i temi ammessi dal database coincidono con quelli dell'app (migrazione e schema.sql)", async () => {
  const app = await avviaApp({utente: U.soc});
  const attesi = [...app.esegui("Object.keys(TEMI)"), "personalizzato", "automatico"].sort();
  for (const f of ["supabase/migrations/20261122_correzioni_retest.sql", "supabase/schema.sql"]) {
    const sql = fs.readFileSync(path.join(radice, f), "utf8");
    const m = sql.match(/impostazioni_tema_valido check \(tema in \(([^)]*)\)\)/);
    assert.ok(m, `vincolo del tema non trovato in ${f}`);
    const nelDb = [...m[1].matchAll(/'([^']+)'/g)].map(x => x[1]).sort();
    assert.deepEqual(nelDb, attesi, `elenco dei temi diverso in ${f}`);
  }
});

// ---------- Partecipanti ----------
test('partecipante "constructor": la scheda attività del direttivo si apre e i doppioni restano segnalati', async () => {
  const dati = datiProva();
  dati.tabelle.adesioni = [
    {id: "a1", attivita_id: "g-futura", user_id: U.soc, nome: "constructor", io: true, acc: [{nome: "toString", rel: "Amico"}], creato_il: "2026-11-01T10:00:00Z"},
    {id: "a2", attivita_id: "g-futura", user_id: U.soc2, nome: "Mario Rossi", io: true, acc: [{nome: "__proto__", rel: "Amico"}], creato_il: "2026-11-02T10:00:00Z"},
    {id: "a3", attivita_id: "g-futura", user_id: null, nome: "Rossi Mario", io: true, acc: [], creato_il: "2026-11-03T10:00:00Z"}
  ];
  const app = await avviaApp({utente: U.pres, dati});
  const ps = app.esegui('partecipanti("g-futura")');
  assert.equal(ps.length, 3);
  // "Mario Rossi" e "Rossi Mario" sono la stessa persona: il controllo dei doppioni funziona ancora
  assert.ok(ps.find(p => p.id === "a2").dups.length > 0 && ps.find(p => p.id === "a3").dups.length > 0);
  assert.equal(ps.find(p => p.id === "a1").dups.length, 0);
  app.esegui('openView("evento", "g-futura")');
  assert.deepEqual(app.errori, [], "nessun errore aprendo la scheda");
  assert.ok(app.ctx.document.querySelector("#sheet").innerHTML.includes("constructor"), "il nome compare (con escape) nella scheda");
});

// ---------- Niente SVG ----------
test("caricamento di un SVG rifiutato prima di arrivare allo Storage (logo, copertine, gallerie)", async () => {
  const app = await avviaApp({utente: U.pres});
  const caricamenti = () => app.sb.st.richieste.filter(r => r.tipo === "upload").length;
  for (const file of [{name: "logo.svg", type: "image/svg+xml", size: 500}, {name: "logo.SVG", type: "", size: 500},
                      {name: "x.svgz", type: "image/svg+xml", size: 500}]) {
    app.ctx.__f = file;
    await assert.rejects(() => app.esegui("api.carica(__f, false)"), e => e.codice === "svg" && /SVG non sono ammesse/.test(e.message));
    await assert.rejects(() => app.esegui("api.carica(__f, true, BKT_GAL)"), e => e.codice === "svg");
  }
  assert.equal(caricamenti(), 0, "nessun SVG inviato allo Storage");
  // Una foto normale si carica ancora
  app.ctx.__f = {name: "foto.png", type: "image/png", size: 500};
  const r = await app.esegui("api.carica(__f, false)");
  assert.equal(r.bucket, "foto"); assert.equal(caricamenti(), 1);
});

test("galleria: un SVG tra le foto non crea righe né file, le altre foto si pubblicano", async () => {
  const app = await avviaApp({utente: U.soc});
  const prima = app.sb.st.tabelle.foto.length;
  app.ctx.__files = [{name: "a.svg", type: "image/svg+xml", size: 100}, {name: "b.gif", type: "image/gif", size: 100}];
  app.esegui("S.dichiaraFoto = true");
  await app.esegui('caricaFoto("g-passata", __files)');
  await app.calma();
  const caricati = app.sb.st.richieste.filter(r => r.tipo === "upload");
  assert.equal(caricati.length, 1); assert.match(caricati[0].percorso, /\.gif$/);
  assert.equal(app.sb.st.tabelle.foto.length, prima + 1);
});

// ---------- Importazione Excel ----------
test("e-mail lunghissima: controllo immediato e rifiutata; le e-mail normali restano valide", () => {
  const ostile = "a".repeat(5000) + "@" + "b".repeat(5000) + "." + "c".repeat(5000);
  const inizio = process.hrtime.bigint();
  assert.equal(I.emailValida(ostile), false);
  assert.equal(I.emailValida("x@" + "a.".repeat(20000)), false);
  const ms = Number(process.hrtime.bigint() - inizio) / 1e6;
  assert.ok(ms < 50, `controllo troppo lento: ${ms.toFixed(1)} ms`);
  assert.equal(I.emailValida("maria.rossi@esempio.it"), true);
  const e254 = "a".repeat(64) + "@" + "b".repeat(186) + ".it", e255 = "a".repeat(64) + "@" + "b".repeat(187) + ".it";
  assert.equal(e254.length, 254); assert.equal(e255.length, 255);
  assert.equal(I.emailValida(e254), true, "254 caratteri: ancora valida");
  assert.equal(I.emailValida(e255), false, "255 caratteri: non valida");
  assert.equal(I.emailValida(""), false);
});

test("riga con molte e-mail ostili: l'anteprima dell'importazione resta veloce", () => {
  const celle = t => ({testo: t, tipo: "testo"});
  const lettura = {righe: Array.from({length: 20}, (_, i) => ({n: i + 2,
    celle: [celle("Rossi Mario " + i), celle("333" + String(1000000 + i)), celle("x".repeat(10000) + "@" + "a.".repeat(5000))]}))};
  const mappa = {nominativo: 0, nome: -1, cognome: -1, telefono: 1, email: 2, tessera: -1};
  const inizio = Date.now();
  const r = I.preparaRighe(lettura, mappa);
  assert.ok(Date.now() - inizio < 500, "preparazione troppo lenta");
  const righe = r.righe || r;
  assert.ok(righe.every(x => x.errori.some(e => /email non valida/.test(e))));
});

test("foglio larghissimo (cella nella colonna XFD): si leggono al massimo 100 colonne", () => {
  const riga = (...v) => v.map(x => x === undefined ? undefined : {t: "s", v: x, w: x});
  const larga = riga("Rossi Mario", "3331112222"); larga[16383] = {t: "s", v: "lontano", w: "lontano"};
  const righe = [riga("Nominativo", "Cellulare"), larga];
  for (let i = 0; i < 3000; i++) righe.push(riga("Socio " + i, "333" + String(2000000 + i)));
  const XLSXfinto = {read: () => ({SheetNames: ["Soci"], Sheets: {Soci: {"!data": righe}}}), SSF: null};
  const inizio = Date.now();
  const r = I.leggiXls(XLSXfinto, new Uint8Array(1));
  assert.ok(Date.now() - inizio < 2000, "lettura troppo lenta");
  assert.equal(r.intestazioni.length, I.IMPORT_MAX_COLONNE);
  assert.equal(r.colonneEscluse, 16384 - I.IMPORT_MAX_COLONNE);
  assert.ok(r.righe.every(x => x.celle.length === I.IMPORT_MAX_COLONNE));
  assert.equal(r.righe[0].celle[0].testo, "Rossi Mario");
  assert.equal(r.righe.length, 3001);
});

test("foglio normale: nessuna colonna esclusa", () => {
  const riga = (...v) => v.map(x => ({t: "s", v: x, w: x}));
  const XLSXfinto = {read: () => ({SheetNames: ["Soci"], Sheets: {Soci: {"!data": [riga("Nominativo", "Cellulare", "Email"), riga("Rossi Mario", "3331112222", "m@esempio.it")]}}}), SSF: null};
  const r = I.leggiXls(XLSXfinto, new Uint8Array(1));
  assert.equal(r.intestazioni.length, 3);
  assert.equal(r.colonneEscluse, 0);
});
