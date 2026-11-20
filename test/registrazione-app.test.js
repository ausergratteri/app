// Interfaccia della registrazione con codice via e-mail, sull'app VERA (app.js) con un
// finto Supabase e una finta funzione server: nessuna rete, nessun invio.
const test = require("node:test");
const assert = require("node:assert/strict");
const {avviaApp, BASE} = require("./ambiente-app.js");

const RICHIESTA = "11111111-2222-4333-8444-555555555555", GETTONE = "a".repeat(64);

// Prepara l'app sulla schermata "Primo accesso" con una funzione server finta
async function app(rispondi) {
  const a = await avviaApp({utente: null});
  const chiamate = [], accessi = [];
  a.ctx.fetch = async (url, opz) => {
    const corpo = JSON.parse(opz.body);
    chiamate.push({url, opz, corpo});
    const [stato, risposta] = rispondi(corpo);
    return {status: stato, async json() { return risposta; }};
  };
  a.sb.client.auth.signInWithPassword = async c => { accessi.push(c); return {error: null}; };
  a.sb.client.auth.signUp = async () => { throw new Error("signUp non deve più essere usato"); };
  a.S.authTab = "registrati"; a.esegui("render()");
  const campo = sel => a.ctx.document.querySelector(sel);
  const evento = {preventDefault() {}};
  return {a, chiamate, accessi, campo, evento, html: () => a.html()};
}
const flussoOk = c => c.azione === "avvia" ? [200, {esito: "ok", richiesta: RICHIESTA, messaggio: "Se i dati corrispondono…"}]
  : c.azione === "verifica" ? (c.codice === "482913" ? [200, {esito: "ok", gettone: GETTONE}] : [400, {esito: "errato", tentativi_rimasti: 3}])
  : c.azione === "completa" ? [200, {esito: "ok"}] : [200, {esito: "ricevuta", messaggio: "Richiesta ricevuta."}];

test("primo passo: solo nome, cognome e telefono; nessun campo e-mail né PIN", async () => {
  const {html} = await app(flussoOk);
  const h = html();
  for (const id of ["rNome", "rCognome", "rTel"]) assert.ok(h.includes(`id="${id}"`), id);
  assert.ok(!/type="email"|id="rEmail"/.test(h), "nessun campo e-mail");
  assert.ok(!h.includes('id="rPin"'), "il PIN si sceglie solo dopo il codice");
  assert.ok(h.includes('data-act="reg-manuale"'), "c'è la strada del direttivo");
});

test("avvio: chiama la funzione server con nome, cognome e telefono (mai un'e-mail) e passa al codice", async () => {
  const {a, chiamate, html} = await app(flussoOk);
  await a.esegui('regAvvia("Giovanni", "Bianchi", "333 444 4444")');
  assert.equal(chiamate.length, 1);
  assert.equal(chiamate[0].url, `${BASE}/functions/v1/registrazione`);
  assert.deepEqual(chiamate[0].corpo, {azione: "avvia", nome: "Giovanni", cognome: "Bianchi", telefono: "333 444 4444"});
  assert.equal(chiamate[0].opz.headers.apikey, "sb_publishable_finto");
  assert.equal(chiamate[0].opz.headers.Authorization, undefined);
  assert.equal(a.S.reg.passo, "codice");
  assert.ok(html().includes('id="rCodice"') && !html().includes('id="rPin"'));
});

test("codice sbagliato: resta sul codice e dice i tentativi rimasti", async () => {
  const {a, campo, evento} = await app(flussoOk);
  await a.esegui('regAvvia("Giovanni", "Bianchi", "3334444444")');
  a.ctx.__ev = evento; campo("#rCodice").value = "111111";
  await a.esegui("regCodice(__ev)");
  assert.equal(a.S.reg.passo, "codice");
  assert.match(campo("#rErr").textContent, /Codice non corretto.*Tentativi rimasti: 3/);
});

test("percorso completo: codice → PIN → registrazione → accesso con telefono e PIN", async () => {
  const {a, chiamate, accessi, campo, evento, html} = await app(flussoOk);
  a.ctx.__ev = evento;
  await a.esegui('regAvvia("Giovanni", "Bianchi", "+39 333 444 4444")');
  campo("#rCodice").value = "482 913";
  await a.esegui("regCodice(__ev)");
  assert.equal(a.S.reg.passo, "pin");
  assert.ok(html().includes('id="rPin"') && html().includes('id="rPin2"'));
  campo("#rPin").value = "135790"; campo("#rPin2").value = "135790";
  await a.esegui("regPin(__ev)");
  assert.deepEqual(chiamate.map(c => c.corpo.azione), ["avvia", "verifica", "completa"]);
  assert.deepEqual(chiamate[2].corpo, {azione: "completa", richiesta: RICHIESTA, gettone: GETTONE, pin: "135790"});
  assert.deepEqual(JSON.parse(JSON.stringify(accessi)), [{email: "3334444444@soci.ausergratteri.app", password: "135790"}]);
  assert.equal(a.S.reg, null, "gettone dimenticato dopo la registrazione");
});

test("PIN: da 6 a 12 cifre e uguali, altrimenti nessuna chiamata", async () => {
  const {a, chiamate, campo, evento} = await app(flussoOk);
  a.ctx.__ev = evento;
  await a.esegui('regAvvia("Giovanni", "Bianchi", "3334444444")');
  campo("#rCodice").value = "482913"; await a.esegui("regCodice(__ev)");
  for (const [p1, p2] of [["12345", "12345"], ["abcdef", "abcdef"], ["135790", "135791"], ["1234567890123", "1234567890123"]]) {
    campo("#rPin").value = p1; campo("#rPin2").value = p2;
    await a.esegui("regPin(__ev)");
  }
  assert.equal(chiamate.filter(c => c.corpo.azione === "completa").length, 0);
});

test("messaggi chiari: troppe richieste, codice scaduto, servizio non raggiungibile", async () => {
  const troppe = await app(() => [429, {esito: "troppe_richieste"}]);
  await troppe.a.esegui('regAvvia("A", "B", "3334444444")');
  assert.match(troppe.campo("#rErr").textContent, /Troppe richieste/);
  const scaduto = await app(c => c.azione === "avvia" ? flussoOk(c) : [410, {esito: "scaduto"}]);
  scaduto.a.ctx.__ev = scaduto.evento;
  await scaduto.a.esegui('regAvvia("A", "B", "3334444444")');
  scaduto.campo("#rCodice").value = "482913"; await scaduto.a.esegui("regCodice(__ev)");
  assert.match(scaduto.campo("#rErr").textContent, /scaduto/);
  const rete = await app(() => { throw new Error("rete"); });
  rete.a.ctx.fetch = async () => { throw new Error("rete giù"); };
  await rete.a.esegui('regAvvia("A", "B", "3334444444")');
  assert.match(rete.campo("#rErr").textContent, /non risponde/);
});

test("strada del direttivo: richiesta manuale con PIN, poi accesso (account in attesa)", async () => {
  const {a, chiamate, accessi, campo, evento, html} = await app(flussoOk);
  a.ctx.__ev = evento;
  a.S.reg = {passo: "manuale"}; a.esegui("render()");
  assert.ok(html().includes('id="rmNome"') && html().includes('id="rmPin"'));
  campo("#rmNome").value = "Anna"; campo("#rmCognome").value = "Verdi"; campo("#rmTel").value = "3335550470";
  campo("#rmPin").value = "246802"; campo("#rmPin2").value = "246802";
  await a.esegui("regManuale(__ev)");
  assert.deepEqual(chiamate[0].corpo, {azione: "manuale", nome: "Anna", cognome: "Verdi", telefono: "3335550470", pin: "246802"});
  assert.deepEqual(JSON.parse(JSON.stringify(accessi)), [{email: "3335550470@soci.ausergratteri.app", password: "246802"}]);
});

test("il gettone della registrazione si cancella all'uscita o al cambio di scheda", async () => {
  const {a, campo, evento} = await app(flussoOk);
  a.ctx.__ev = evento;
  await a.esegui('regAvvia("Giovanni", "Bianchi", "3334444444")');
  campo("#rCodice").value = "482913"; await a.esegui("regCodice(__ev)");
  assert.equal(a.S.reg.gettone, GETTONE);
  a.esegui("azzeraDatiSessione()");
  assert.equal(a.S.reg, null);
});
