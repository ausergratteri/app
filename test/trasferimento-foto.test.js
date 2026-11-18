// Script di trasferimento delle foto (supabase/operazioni/foto-private.js) contro un
// finto Supabase in memoria: nessuna rete, nessuna chiave vera.
const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../supabase/operazioni/foto-private.js");

const URL_P = "https://progettofinto.supabase.co";
const CHIAVE = "sb_secret_CHIAVE-DI-PROVA-1234567890";

function supabaseFinto({righe, pubblici, privati = {}, tabelle = {}}) {
  const st = {
    righe: righe.map(r => ({...r})),
    file: {foto: new Map(Object.entries(pubblici)), "foto-private": new Map(Object.entries(privati))},
    tabelle: {attivita: [], bacheca: [], impostazioni: [], ...tabelle},
    chiamate: [], rottiInUpload: new Set(), corrompi: new Set()
  };
  const risposta = (status, corpo, tipo = "application/json") => ({
    ok: status >= 200 && status < 300, status,
    headers: {get: k => k.toLowerCase() === "content-type" ? tipo : null},
    async json() { return JSON.parse(corpo); },
    async text() { return String(corpo); },
    async arrayBuffer() { const b = Buffer.from(corpo); return b.buffer.slice(b.byteOffset, b.byteOffset + b.length); }
  });
  async function fetch(url, opz = {}) {
    const u = new URL(url);
    const metodo = opz.method || "GET";
    st.chiamate.push({metodo, percorso: u.pathname});
    assert.equal(opz.headers.apikey, CHIAVE);
    if (u.pathname.startsWith("/rest/v1/")) {
      const t = u.pathname.slice(9);
      const tutte = t === "foto" ? st.righe : st.tabelle[t];
      const da = Number(u.searchParams.get("offset")), n = Number(u.searchParams.get("limit"));
      return risposta(200, JSON.stringify(tutte.slice(da, da + n)));
    }
    let m = u.pathname.match(/^\/storage\/v1\/object\/authenticated\/([^/]+)\/(.+)$/);
    if (m && metodo === "GET") {
      const p = decodeURIComponent(m[2]), b = st.file[m[1]].get(p);
      return b === undefined ? risposta(400, '{"error":"not_found"}') : risposta(200, b, "image/jpeg");
    }
    m = u.pathname.match(/^\/storage\/v1\/object\/([^/]+)\/(.+)$/);
    if (m && metodo === "POST") {
      const p = decodeURIComponent(m[2]);
      if (st.rottiInUpload.has(p)) return risposta(500, st.echoChiave ? "chiave ricevuta: " + opz.headers.apikey : "errore interno");
      if (opz.headers["x-upsert"] !== "false") throw new Error("upload senza x-upsert false");
      if (st.file[m[1]].has(p)) return risposta(400, '{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}');
      st.file[m[1]].set(p, st.corrompi.has(p) ? "CORROTTO" : Buffer.from(opz.body).toString());
      return risposta(200, '{"Key":"x"}');
    }
    m = u.pathname.match(/^\/storage\/v1\/object\/([^/]+)$/);
    if (m && metodo === "DELETE") {
      JSON.parse(opz.body).prefixes.forEach(p => st.file[m[1]].delete(p));
      return risposta(200, "[]");
    }
    return risposta(404, "sconosciuto");
  }
  return {st, sb: T.creaClient({url: URL_P, chiave: CHIAVE, fetch})};
}

const RIGHE = [
  {id: "1", percorso: "u1/1-a.jpg", bucket: "foto", user_id: "u1"},
  {id: "2", percorso: "u1/2-b.jpg", bucket: "foto", user_id: "u1"},
  {id: "3", percorso: "u2/3-c.jpg", user_id: "u2"},                       // riga senza colonna bucket
  {id: "4", percorso: "u2/4-manca.jpg", bucket: "foto", user_id: "u2"},   // file pubblico mancante
  {id: "5", percorso: "", bucket: "foto", user_id: null}                  // riga vecchia senza percorso
];
const PUBBLICI = {"u1/1-a.jpg": "AAA", "u1/2-b.jpg": "BBB", "u2/3-c.jpg": "CCC", "p/copertina.jpg": "COP"};
const COPERTINE = {attivita: [{id: "x", immagine: `${URL_P}/storage/v1/object/public/foto/p/copertina.jpg`}, {id: "y", immagine: "locandine/a.jpg"}],
  bacheca: [], impostazioni: [{id: 1, logo: ""}]};
const silenzio = () => {};

test("trasferimento: chiave pubblica o indirizzo sbagliato rifiutati", () => {
  assert.throws(() => T.creaClient({url: URL_P, chiave: "sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxx"}), /chiave secret/);
  assert.throws(() => T.creaClient({url: "https://esempio.it", chiave: CHIAVE}), /SUPABASE_URL/);
  assert.throws(() => T.creaClient({url: URL_P, chiave: ""}), /Manca la chiave/);
});

test("trasferimento: piano solo in lettura, con i numeri giusti", async () => {
  const {st, sb} = supabaseFinto({righe: RIGHE, pubblici: PUBBLICI, tabelle: COPERTINE});
  const e = await T.piano(sb, silenzio);
  assert.equal(e.righe, 5);
  assert.equal(e.da_copiare, 4);
  assert.equal(e.senza_percorso, 1);
  assert.equal(e.copertine_bacheca_logo_nel_bucket, 1);
  assert.ok(st.chiamate.every(c => c.metodo === "GET"));
});

test("trasferimento: copia e verifica ogni file, non tocca le copie pubbliche né le righe", async () => {
  const {st, sb} = supabaseFinto({righe: RIGHE, pubblici: PUBBLICI, tabelle: COPERTINE});
  const reg = await T.copia(sb, silenzio);
  const esito = Object.fromEntries(reg.map(v => [v.id, v.esito]));
  assert.deepEqual(esito, {"1": "copiata-verificata", "2": "copiata-verificata", "3": "copiata-verificata", "4": "manca-in-foto"});
  assert.equal(st.file["foto-private"].get("u1/1-a.jpg"), "AAA");
  assert.equal(st.file.foto.size, 4, "nessun file pubblico tolto");
  assert.ok(!st.file["foto-private"].has("p/copertina.jpg"), "la copertina non si copia");
  assert.ok(st.chiamate.every(c => !(c.metodo !== "GET" && c.percorso.startsWith("/rest/"))), "nessuna scrittura sul database");
  assert.match(reg.find(v => v.id === "1").sha256, /^[0-9a-f]{64}$/);
  // Ripetibile: la seconda volta riconosce le copie già fatte
  const reg2 = await T.copia(sb, silenzio);
  assert.equal(reg2.find(v => v.id === "1").esito, "gia-presente-identica");
});

test("trasferimento: copia privata già presente ma diversa → segnalata, non sovrascritta", async () => {
  const {st, sb} = supabaseFinto({righe: RIGHE.slice(0, 1), pubblici: PUBBLICI, privati: {"u1/1-a.jpg": "ALTRO"}});
  const reg = await T.copia(sb, silenzio);
  assert.equal(reg[0].esito, "DIVERSA-gia-presente");
  assert.equal(st.file["foto-private"].get("u1/1-a.jpg"), "ALTRO");
});

test("trasferimento: file arrivato corrotto o errore del server → segnalati", async () => {
  const {st, sb} = supabaseFinto({righe: RIGHE.slice(0, 2), pubblici: PUBBLICI});
  st.corrompi.add("u1/1-a.jpg"); st.rottiInUpload.add("u1/2-b.jpg");
  const reg = await T.copia(sb, silenzio);
  assert.equal(reg[0].esito, "VERIFICA-FALLITA");
  assert.match(reg[1].esito, /^ERRORE/);
});

test("trasferimento: eliminazione delle copie pubbliche solo con conferma esplicita", async () => {
  const {st, sb} = supabaseFinto({righe: RIGHE, pubblici: PUBBLICI, tabelle: COPERTINE});
  await assert.rejects(() => T.eliminaPubbliche(sb, silenzio, {}), /--conferma/);
  await assert.rejects(() => T.eliminaPubbliche(sb, silenzio, {conferma: "si"}), /--conferma/);
  assert.equal(st.file.foto.size, 4);
});

test("trasferimento: si tolgono solo copie pubbliche di righe attivate e con copia privata identica", async () => {
  const righe = [
    {id: "1", percorso: "u1/1-a.jpg", bucket: "foto-private"},   // attivata, copie identiche → si toglie
    {id: "2", percorso: "u1/2-b.jpg", bucket: "foto-private"},   // attivata ma copia privata diversa → si tiene
    {id: "3", percorso: "u2/3-c.jpg", bucket: "foto"},           // non attivata → non si guarda
    {id: "6", percorso: "p/copertina.jpg", bucket: "foto-private"} // usata come copertina → protetta
  ];
  const {st, sb} = supabaseFinto({righe, pubblici: PUBBLICI, privati: {"u1/1-a.jpg": "AAA", "u1/2-b.jpg": "XXX", "p/copertina.jpg": "COP"}, tabelle: COPERTINE});
  const reg = await T.eliminaPubbliche(sb, silenzio, {conferma: T.CONFERMA_ELIMINA});
  const esito = Object.fromEntries(reg.map(v => [v.id, v.esito]));
  assert.deepEqual(esito, {"1": "tolta-copia-pubblica", "2": "TENUTA: copie diverse", "6": "protetta-copertina-bacheca-logo"});
  assert.deepEqual([...st.file.foto.keys()].sort(), ["p/copertina.jpg", "u1/2-b.jpg", "u2/3-c.jpg"]);
  assert.equal(st.file["foto-private"].get("u1/1-a.jpg"), "AAA");
});

test("trasferimento: rollback dei file — ricopia nel bucket pubblico solo ciò che manca", async () => {
  const righe = [
    {id: "1", percorso: "u1/1-a.jpg", bucket: "foto-private"},   // pubblica tolta → da riportare
    {id: "2", percorso: "u1/2-b.jpg", bucket: "foto-private"}    // pubblica ancora presente
  ];
  const {st, sb} = supabaseFinto({righe, pubblici: {"u1/2-b.jpg": "BBB"}, privati: {"u1/1-a.jpg": "AAA", "u1/2-b.jpg": "BBB"}});
  const reg = await T.copia(sb, silenzio, {da: "foto-private", a: "foto", soloSenzaCopia: true});
  assert.deepEqual(reg.map(v => v.esito), ["copiata-verificata", "gia-presente"]);
  assert.equal(st.file.foto.get("u1/1-a.jpg"), "AAA");
});

test("trasferimento: la chiave non compare mai nei messaggi né nel registro", async () => {
  // Il server finto, in caso di errore, rimanda indietro la chiave ricevuta (caso peggiore)
  const {st, sb} = supabaseFinto({righe: [{id: "1", percorso: "u1/1-a.jpg", bucket: "foto"}], pubblici: PUBBLICI});
  st.rottiInUpload.add("u1/1-a.jpg");
  st.echoChiave = true;
  const log = [];
  const reg = await T.copia(sb, m => log.push(m));
  assert.match(reg[0].esito, /^ERRORE/);
  const tutto = log.join("\n") + T.csv(reg) + JSON.stringify(reg);
  assert.ok(tutto.includes("***"), "la chiave rimandata dal server deve essere oscurata");
  assert.ok(!tutto.includes(CHIAVE));
});

test("trasferimento: senza cartella del registro il comando non parte", async () => {
  const log = [];
  const codice = await T.principale(["copia"], {SUPABASE_URL: URL_P, SUPABASE_SERVICE_ROLE_KEY: CHIAVE}, m => log.push(m));
  assert.equal(codice, 2);
  assert.match(log.join(" "), /--uscita/);
});
