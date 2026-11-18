// Lettura dei .xls del gestionale: telefoni e numeri tessera non devono cambiare.
// Usa la copia locale di SheetJS (vendor/), la stessa che carica l'app.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const XLSX = require("../vendor/sheetjs-0.20.3/xlsx.full.min.js");
const I = require("../importa-xls.js");

const radice = path.join(__dirname, "..");
const libro = celle => {
  const ws = {...celle};
  const ref = Object.keys(celle).filter(k => /^[A-Z]+\d+$/.test(k));
  const maxR = Math.max(...ref.map(k => +k.replace(/\D/g, ""))), maxC = Math.max(...ref.map(k => k.replace(/\d/g, "").charCodeAt(0) - 64));
  ws["!ref"] = "A1:" + String.fromCharCode(64 + maxC) + maxR;
  return {SheetNames: ["Soci"], Sheets: {Soci: ws}};
};
const comeFile = (wb, bookType) => new Uint8Array(XLSX.write(wb, {bookType, type: "array"}));

// Intestazioni come potrebbero arrivare dal gestionale, con i casi difficili
const CASI = libro({
  A1: {t: "s", v: "N° Tessera"}, B1: {t: "s", v: "Cognome"}, C1: {t: "s", v: "Nome"}, D1: {t: "s", v: "Cellulare"}, E1: {t: "s", v: "E-mail"}, F1: {t: "s", v: "Data nascita"},
  A2: {t: "s", v: "000123"},            B2: {t: "s", v: "Rossi"},  C2: {t: "s", v: "Maria"},     D2: {t: "n", v: 3331234567},            E2: {t: "s", v: "Maria@Example.it "},
  A3: {t: "n", v: 124, z: "000000"},    B3: {t: "s", v: "Bianchi"}, C3: {t: "s", v: "Giovanni"}, D3: {t: "n", v: 393334444444},          E3: {t: "s", v: ""},
  A4: {t: "n", v: 2026000125},          B4: {t: "s", v: "Lo Bue"}, C4: {t: "s", v: "Niccolò"},   D4: {t: "s", v: "+39 333 555 5555"},    E4: {t: "s", v: "nonna@example.it"},
  A5: {t: "s", v: "PA-2026/0045"},      B5: {t: "s", v: "Fisso"},  C5: {t: "s", v: "Pina"},      D5: {t: "s", v: "0921 123456"},         E5: {t: "s", v: "nonna@example.it"},
  A6: {t: "s", v: "000127"},            B6: {t: "s", v: "Zero"},   C6: {t: "s", v: "Perso"},     D6: {t: "n", v: 921654321},             E6: {t: "s", v: "z@example.it"},
  A7: {t: "s", v: "000128"},            B7: {t: "s", v: "Due"},    C7: {t: "s", v: "Numeri"},    D7: {t: "s", v: "333/1234000 - 091 222333"},
  A8: {t: "s", v: "000129"},            B8: {t: "s", v: "Deci"},   C8: {t: "s", v: "Male"},      D8: {t: "n", v: 3331234567.5},
  A9: {t: "s", v: "000130"},            B9: {t: "s", v: "Lungo"},  C9: {t: "s", v: "Troppo"},    D9: {t: "n", v: 12345678901234567},
  A10: {t: "s", v: "000123"},           B10: {t: "s", v: "Doppia"}, C10: {t: "s", v: "Tessera"}, D10: {t: "s", v: "3337777777"},         E10: {t: "s", v: "non-una-email"},
  A11: {t: "s", v: "000131"},           B11: {t: "s", v: "Barra"}, C11: {t: "s", v: "Classica"}, D11: {t: "s", v: "333/1239999"},         F11: {t: "n", v: 20000, z: "dd/mm/yyyy"}
});

for (const formato of ["biff8", "xlml"]) {
  test(`${formato}: telefoni e tessere letti senza alterazioni`, () => {
    const l = I.leggiXls(XLSX, comeFile(CASI, formato));
    assert.deepEqual(l.intestazioni, ["N° Tessera", "Cognome", "Nome", "Cellulare", "E-mail", "Data nascita"], "intestazioni originali");
    const col = (n, j) => l.righe.find(r => r.n === n).celle[j].testo;
    assert.equal(col(2, 0), "000123", "tessera testo con zeri");
    assert.equal(col(3, 0), "000124", "tessera numerica con formato 000000");
    assert.equal(col(4, 0), "2026000125");
    assert.equal(col(5, 0), "PA-2026/0045");
    assert.equal(col(2, 3), "3331234567", "cellulare numerico");
    assert.equal(col(3, 3), "393334444444", "12 cifre in formato Generale: NON 3.93333E+11");
    assert.equal(col(4, 3), "+39 333 555 5555", "testo con prefisso intatto");
    assert.equal(col(5, 3), "0921 123456", "fisso con zero iniziale intatto");
    assert.equal(col(6, 3), "921654321", "zero già perso nel file: non si inventa");
    assert.ok(l.righe.find(r => r.n === 8).celle[3].errore, "decimali segnalati");
    assert.ok(l.righe.find(r => r.n === 9).celle[3].errore, "oltre 15 cifre segnalato");
    assert.equal(col(4, 2), "Niccolò", "accenti");
  });
}

test("falso .xls in HTML (export frequente dei gestionali): i numeri restano testo", () => {
  const html = new TextEncoder().encode('<table><tr><td>Cellulare</td><td>N. Tessera</td><td>Nominativo</td></tr>' +
    '<tr><td>0921123456</td><td>000123</td><td>Pina Fisso</td></tr><tr><td>393331234567</td><td>0045</td><td>Ugo</td></tr></table>');
  const l = I.leggiXls(XLSX, html);
  assert.equal(l.righe[0].celle[0].testo, "0921123456");
  assert.equal(l.righe[0].celle[1].testo, "000123");
  assert.equal(l.righe[1].celle[0].testo, "393331234567");
  assert.equal(l.righe[1].celle[1].testo, "0045");
});

test("riconoscimento delle colonne e controlli riga per riga", () => {
  const l = I.leggiXls(XLSX, comeFile(CASI, "biff8"));
  const m = I.mappaColonne(l.intestazioni);
  assert.deepEqual(m, {tessera: 0, nominativo: -1, cognome: 1, nome: 2, telefono: 3, email: 4});
  const r = Object.fromEntries(I.preparaRighe(l, m).map(x => [x.n, x]));
  assert.equal(r[2].nome, "Maria Rossi");
  assert.equal(r[2].email, "maria@example.it");
  assert.equal(r[2].telefono, "3331234567");
  assert.deepEqual(r[2].errori, ["numero tessera ripetuto nelle righe 2, 10"], "unico errore: la tessera ripetuta apposta nella riga 10");
  assert.equal(r[3].telefono, "3334444444", "prefisso 39 tolto come fa l'app al login");
  assert.equal(r[3].tessera, "000124");
  assert.ok(r[3].avvisi.some(a => /senza email/.test(a)));
  assert.equal(r[4].telefono, "3335555555");
  assert.equal(r[5].telefono, "0921123456");
  assert.ok(r[4].avvisi.some(a => /email usata anche/.test(a)) && r[5].avvisi.some(a => /email usata anche/.test(a)), "email di famiglia: avviso, non errore");
  assert.ok(r[6].avvisi.some(a => /zero iniziale/.test(a)), "zero perso: avviso");
  assert.ok(r[7].errori.some(e => /più numeri/.test(e)));
  assert.ok(r[8].errori.some(e => /decimali/.test(e)));
  assert.ok(r[9].errori.some(e => /troppo lungo/.test(e)));
  assert.ok(r[10].errori.some(e => /email non valida/.test(e)));
  assert.ok(r[2].errori.some(e => /tessera ripetuto/.test(e)) && r[10].errori.some(e => /tessera ripetuto/.test(e)));
  assert.deepEqual(r[11].errori, [], "333/1234567 è un solo numero");
  assert.equal(r[11].telefono, "3331239999");
});

test("intestazione unica 'Nominativo' e colonne con nomi diversi", () => {
  assert.deepEqual(I.mappaColonne(["Nominativo", "Tel. cellulare", "Indirizzo e-mail", "Nr. tessera"]),
    {tessera: 3, nominativo: 0, cognome: -1, nome: -1, telefono: 1, email: 2});
  assert.equal(I.mappaColonne(["Cognome", "Nome", "Telefono", "Cellulare"]).telefono, 3, "il cellulare ha la precedenza");
});

test("confronto con l'anagrafica: nessuna sovrascrittura automatica", () => {
  const righe = [
    {n: 2, nome: "Maria Rossi", telOriginale: "3331111111", telefono: "3331111111", chiave: "3331111111", email: "maria@x.it", tessera: "000123", errori: [], avvisi: []},
    {n: 3, nome: "Gio Bianchi", telOriginale: "3332222222", telefono: "3332222222", chiave: "3332222222", email: "gio@x.it", tessera: "000124", errori: [], avvisi: []},
    {n: 4, nome: "Nuova Socia", telOriginale: "3333333333", telefono: "3333333333", chiave: "3333333333", email: "", tessera: "000125", errori: [], avvisi: []},
    {n: 5, nome: "Altro", telOriginale: "3334444444", telefono: "3334444444", chiave: "3334444444", email: "", tessera: "000999", errori: [], avvisi: []}
  ];
  const esistenti = [
    {id: "t1", nome: "Maria Rossi", telefono: "333 111 1111", email: "MARIA@x.it", numero_tessera: "000123"},
    {id: "t2", nome: "Giovanni Bianchi", telefono: "+39 3332222222", email: "", numero_tessera: "000124"},
    {id: "t9", nome: "Pino", telefono: "3339999999", email: "", numero_tessera: "000999"}
  ];
  const e = I.confrontaAnagrafica(righe, esistenti);
  assert.deepEqual(e.uguali.map(r => r.n), [2], "email uguale a parte le maiuscole");
  assert.deepEqual(e.nuovi.map(r => r.n), [4]);
  assert.deepEqual(e.errori.map(r => r.n), [5], "tessera già di un altro tesserato");
  assert.equal(e.diversi.length, 1);
  assert.deepEqual(e.diversi[0].diff.map(d => [d.campo, d.vuoto]), [["nome", false], ["email", true]]);

  assert.deepEqual(I.pianoImport(e).aggiornamenti, [], "di base non si aggiorna nulla");
  assert.deepEqual(I.pianoImport(e, {completaVuoti: true}).aggiornamenti.map(a => a.campi), [{email: "gio@x.it"}], "solo i campi vuoti");
  assert.deepEqual(I.pianoImport(e, {aggiorna: [3]}).aggiornamenti.map(a => a.campi), [{nome: "Gio Bianchi", email: "gio@x.it"}]);
  assert.equal(I.pianoImport(e, {aggiorna: [3]}).aggiornamenti[0].attuali.nome, "Giovanni Bianchi", "si inviano i valori visti, per non sovrascrivere modifiche altrui");
  assert.deepEqual(I.pianoImport(e).nuovi.map(n => n.telefono), ["3333333333"]);
});

test("report CSV: nessuna formula eseguibile all'apertura in Excel", () => {
  const csv = I.csvReport({errori: [{n: 2, nome: "=HYPERLINK(\"http://x\")", telOriginale: "+39 333", email: "@x", tessera: "-1", errori: ["e"]}], diversi: [], nuovi: [], uguali: []});
  assert.match(csv, /"'=HYPERLINK\(""http:\/\/x""\)"/);
  assert.match(csv, /"'\+39 333"/);
  assert.match(csv, /"'@x"/);
  assert.match(csv, /"'-1"/);
});

test("app.js: l'importazione è solo del presidente (pulsante, apertura e conferma)", () => {
  const js = fs.readFileSync(path.join(radice, "app.js"), "utf8");
  const pulsanti = js.split("\n").filter(l => l.includes('data-act="importa"'));
  assert.equal(pulsanti.length, 1, "un solo pulsante di importazione");
  assert.match(pulsanti[0], /can\("presidente"\)\s*\?/, "il pulsante compare solo se presidente");
  assert.match(js, /function formImporta\(\) \{\s*(\/\/.*\s*)*if \(!can\("presidente"\)\)/, "il modulo non si apre per gli altri ruoli");
  assert.match(js, /case "imp-conferma": \{\s*if \(!IMP \|\| !IMP\.esito \|\| !can\("presidente"\)\) return;/, "la conferma è bloccata per gli altri ruoli");
});

test("migrazione e schema: importa_tesserati controlla nel database che sia il presidente", () => {
  for (const f of ["supabase/migrations/20261119_importa_tesserati.sql", "supabase/schema.sql"]) {
    const sql = fs.readFileSync(path.join(radice, f), "utf8");
    const corpo = sql.slice(sql.indexOf("create or replace function public.importa_tesserati"));
    assert.match(corpo.slice(0, 1200), /if public\.livello\(\) < 3 then raise exception/, f);
    assert.ok(!/livello\(\) < 2/.test(corpo.slice(0, 1200)), f + ": nessun controllo più largo");
    assert.match(sql, /revoke execute on function public\.importa_tesserati\(jsonb, jsonb, text, int\) from public, anon;/, f);
  }
});

test("messaggioErrore: rifiuto dell'importazione spiegato", () => {
  const {messaggioErrore} = require("../sicurezza.js");
  assert.equal(messaggioErrore("Non puoi importare i tesserati: solo il presidente"), "Solo il presidente può importare i tesserati.");
});

test("libreria locale: versione, licenza, integrità e nessun eval", () => {
  const dir = path.join(radice, "vendor/sheetjs-0.20.3");
  assert.equal(XLSX.version, "0.20.3");
  assert.match(fs.readFileSync(path.join(dir, "LICENSE"), "utf8"), /Apache License/);
  const js = fs.readFileSync(path.join(dir, "xlsx.full.min.js"));
  const sri = "sha384-" + crypto.createHash("sha384").update(js).digest("base64");
  assert.ok(fs.readFileSync(path.join(radice, "app.js"), "utf8").includes(sri), "app.js carica la libreria con l'integrity giusta");
  assert.ok(!/\beval\(|new Function|XMLHttpRequest|\bfetch\(/.test(js.toString()), "nessun eval o rete");
});
