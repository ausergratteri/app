// Strumenti del presidente sull'app VERA (app.js) con un finto Supabase: e-mail dei tesserati e
// azzeramento del primo accesso. Il controllo vero del ruolo è nel database (test/sql/49_…).
const test = require("node:test");
const assert = require("node:assert/strict");
const {avviaApp, U} = require("./ambiente-app.js");

const rpc = (a, fn) => a.sb.st.richieste.filter(r => r.tipo === "rpc" && r.fn === fn);

test("presidente: vede «Azzera primo accesso» per gli altri ma non per sé stesso", async () => {
  const a = await avviaApp({utente: U.pres});
  const h = a.esegui("vSoci()");
  for (const id of [U.soc, U.soc2, U.att]) assert.ok(h.includes(`data-act="azzera-accesso" data-id="${id}"`), id);
  assert.ok(!h.includes(`data-act="azzera-accesso" data-id="${U.pres}"`), "mai su sé stesso");
});

test("presidente: vede il pulsante «E-mail» accanto ai tesserati", async () => {
  const a = await avviaApp({utente: U.pres});
  assert.ok(a.esegui("vSoci()").includes('data-act="email-tesserato" data-id="t1"'));
});

test("direttivo (vista): nessun pulsante per e-mail o azzeramento", async () => {
  const a = await avviaApp({utente: U.pres});
  a.S.viewRole = "direttivo";
  const h = a.esegui("vSoci()");
  assert.ok(!h.includes('data-act="azzera-accesso"'));
  assert.ok(!h.includes('data-act="email-tesserato"'));
});

test("e-mail: salvata in minuscolo e senza spazi con la funzione del database", async () => {
  const a = await avviaApp({utente: U.pres});
  await a.esegui(`salvaEmailTesserato("t1", "  Nuova.Email@Esempio.IT ")`);
  const c = rpc(a, "imposta_email_tesserato");
  assert.equal(c.length, 1);
  assert.deepEqual({...c[0].args}, {p_tesserato: "t1", p_email: "nuova.email@esempio.it"});
});

test("e-mail: indirizzo non valido → nessuna chiamata, messaggio nel modulo", async () => {
  const a = await avviaApp({utente: U.pres});
  await a.esegui(`salvaEmailTesserato("t1", "non-valida@")`);
  assert.equal(rpc(a, "imposta_email_tesserato").length, 0);
  assert.match(a.ctx.document.querySelector("#etErr").textContent, /Controlla l'indirizzo e-mail/);
});

test("e-mail: vuota → si toglie (chiamata con stringa vuota)", async () => {
  const a = await avviaApp({utente: U.pres});
  await a.esegui(`salvaEmailTesserato("t1", "   ")`);
  assert.deepEqual({...rpc(a, "imposta_email_tesserato")[0].args}, {p_tesserato: "t1", p_email: ""});
});

test("messaggi chiari per gli errori del database", async () => {
  const a = await avviaApp({utente: U.pres});
  const m = s => a.esegui(`messaggioErrore(${JSON.stringify(s)})`);
  assert.match(m("Ha già iscrizioni o foto: non si può azzerare, usa Nuovo PIN"), /Nuovo PIN/);
  assert.match(m("Non puoi azzerare il tuo primo accesso"), /tuo primo accesso/);
  assert.match(m("Non puoi azzerare il primo accesso di un presidente"), /presidente/);
  assert.match(m("Solo il presidente può azzerare il primo accesso"), /Solo il presidente/);
  assert.match(m("Solo il presidente può cambiare l'e-mail di un tesserato"), /Solo il presidente/);
  assert.match(m("E-mail non valida"), /Controlla l'indirizzo/);
});
