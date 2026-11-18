const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("logout: una richiesta precedente non ripristina i dati", async () => {
  const js = fs.readFileSync(path.join(__dirname, "../app.js"), "utf8");
  const inizio = js.indexOf("async function carica() {");
  const fine = js.indexOf("\n}\n", inizio);

  assert.ok(inizio >= 0 && fine > inizio, "Funzione carica non trovata");

  let completaRichieste;
  const inAttesa = new Promise(resolve => {
    completaRichieste = resolve;
  });

  const query = () => ({
    select() { return this; },
    order() { return this; },
    eq() { return this; },
    maybeSingle() { return inAttesa; },
    then(ok, errore) { return inAttesa.then(ok, errore); }
  });

  const S = {
    live: true,
    realRole: "socio",
    sessione: {user: {id: "socio-1"}},
    sb: {from: query, rpc: () => inAttesa},
    foto: [],
    att: {}
  };

  let aggiornamenti = 0;
  const contesto = {
    S,
    RANK: {socio: 1},
    refresh: () => aggiornamenti++,
    console
  };

  vm.runInNewContext(
    js.slice(inizio, fine + 2) + "\nglobalThis.caricaDaTest = carica;",
    contesto
  );

  const caricamento = contesto.caricaDaTest();

  // Il socio esce mentre Supabase sta rispondendo.
  S.sessione = null;
  S._versioneCarica++;
  S.foto = [];

  // Arrivano le risposte della sessione precedente.
  completaRichieste({data: [], error: null});
  await caricamento;

  assert.equal(S.foto.length, 0, "Le foto non devono ricomparire");
  assert.equal(aggiornamenti, 0, "La schermata non deve aggiornarsi");
});
