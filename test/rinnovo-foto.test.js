const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const js = fs.readFileSync(path.join(__dirname, "../app.js"), "utf8");
const inizio = js.indexOf("async function rinnovaFoto() {");
const fine = js.indexOf("\n}\n", inizio);

assert.ok(inizio >= 0 && fine > inizio, "Funzione rinnovaFoto non trovata");

function prepara(firmaFoto, minuti = 46) {
  const originali = [{
    id: "foto1",
    percorso: "utente/foto.jpg",
    url: "https://esempio.it/public/foto.jpg"
  }];

  const S = {
    live: true,
    realRole: "socio",
    sessione: {user: {id: "utente"}},
    _versioneCarica: 1,
    _fotoDaFirmare: originali,
    _fotoFirmateAlle: Date.now() - minuti * 60000,
    foto: [...originali],
    sb: {storage: {from: () => ({})}},
    fotoErrore: false
  };

  let aggiornamenti = 0;
  const contesto = {
    S,
    RANK: {socio: 1},
    // rinnovaFoto usa firmaGallerie ({foto, scartate}); qui si adatta la firma finta dei test
    firmaGallerie: async (...argomenti) => ({foto: await firmaFoto(...argomenti), scartate: 0}),
    RINNOVO_FOTO_MS: 45 * 60 * 1000,
    SCADENZA_SICURA_MS: 55 * 60 * 1000,
    DURATA_URL_FOTO: 3600,
    refresh: () => aggiornamenti++,
    LB: null,
    disegnaLB: () => {},
    chiudiLB: () => {},
    console: {error: () => {}},
    Date
  };

  vm.runInNewContext(
    js.slice(inizio, fine + 2) + "\nglobalThis.esegui = rinnovaFoto;",
    contesto
  );

  return {
    S,
    esegui: contesto.esegui,
    aggiornamenti: () => aggiornamenti
  };
}

test("rinnova gli URL temporanei dopo 45 minuti", async () => {
  const x = prepara(async foto =>
    foto.map(f => ({...f, url: "https://esempio.it/signed/foto.jpg?token=ok"}))
  );

  await x.esegui();

  assert.match(x.S.foto[0].url, /signed/);
  assert.doesNotMatch(x.S.foto[0].url, /public/);
  assert.equal(x.aggiornamenti(), 1);
  assert.ok(Date.now() - x.S._fotoFirmateAlle < 5000);
});

test("logout durante il rinnovo: non ripristina le fotografie", async () => {
  let completa;
  const attesa = new Promise(resolve => { completa = resolve; });
  const x = prepara(() => attesa);

  const richiesta = x.esegui();

  x.S.sessione = null;
  x.S._versioneCarica++;
  x.S.foto = [];

  completa([{id: "foto1", url: "https://esempio.it/signed/foto.jpg"}]);
  await richiesta;

  assert.equal(x.S.foto.length, 0);
  assert.equal(x.aggiornamenti(), 0);
});

test("rinnovo fallito: nasconde URL prossimi alla scadenza", async () => {
  const x = prepara(async () => {
    throw new Error("Storage non disponibile");
  }, 56);

  await x.esegui();

  assert.equal(x.S.foto.length, 0);
  assert.equal(x.S.fotoErrore, true);
  assert.equal(x.aggiornamenti(), 1);
});
