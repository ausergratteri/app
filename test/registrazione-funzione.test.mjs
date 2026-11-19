// Test della funzione server "registrazione" (supabase/functions/registrazione/logica.ts)
// con database, e-mail e account SIMULATI: nessuna rete, nessun invio reale.
import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import {gestisci, codiceDaByte, messaggioEmail, ipDaIntestazioni, MESSAGGIO_AVVIO, MESSAGGIO_MANUALE} from "../supabase/functions/registrazione/logica.ts";

const RICHIESTA = "11111111-2222-4333-8444-555555555555";
const GETTONE = "a".repeat(64);
const PEPE = "pepe-di-prova-solo-per-i-test-0123456789";
const hmac = t => crypto.createHmac("sha256", PEPE).update(t).digest("hex");
const sha = t => crypto.createHash("sha256").update(t).digest("hex");

// Dipendenze finte: registrano tutto; "risposte" decide cosa restituisce il database
function finte({risposte = {}, consentite = null, codice = "482913", creaErrore = null, pinErrore = null} = {}) {
  const st = {rpc: [], creati: [], pin: [], email: [], log: [], dopo: [], ordine: []};
  const d = {
    async rpc(f, a) { st.rpc.push({f, a}); st.ordine.push("rpc:" + f); const r = risposte[f]; return typeof r === "function" ? r(a) : (r || []); },
    async creaUtente(u) { st.creati.push(u); st.ordine.push("crea"); return creaErrore ? {errore: creaErrore} : {id: "99999999-2222-4333-8444-555555555555"}; },
    async aggiornaPin(id, pin) { st.pin.push({id, pin}); st.ordine.push("pin"); return pinErrore ? {errore: pinErrore} : {}; },
    async inviaEmail(m) { st.email.push(m); },
    hmac: async t => hmac(t),
    sha256: async t => sha(t),
    codice: () => codice,
    dopo: p => { st.dopo.push(p); },
    log: (evento, dati) => st.log.push(JSON.stringify({evento, ...(dati || {})})),
    emailConsentite: consentite,
    dominio: "soci.ausergratteri.app"
  };
  return {d, st};
}
const avviaRisposta = (invia, email = "giovanni@esempio.it") => ({registrazione_avvia: [{richiesta: RICHIESTA, esito: "ok", invia, email: invia ? email : null, nome: invia ? "Bianchi Giovanni" : null}]});
const DATI = {azione: "avvia", nome: "Giovanni", cognome: "Bianchi", telefono: "333 444 4444"};
const segreti = (st, ...valori) => st.log.join("\n").match(new RegExp(valori.map(v => v.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|"), "g"));

// ---------- avvia ----------
test("avvia: al database arrivano solo impronte HMAC (codice e IP), mai il codice", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  await gestisci(DATI, "203.0.113.7", d);
  const a = st.rpc[0].a;
  assert.equal(a.p_otp_hash, hmac("otp:482913"));
  assert.equal(a.p_ip_hash, hmac("ip:203.0.113.7"));
  assert.ok(!JSON.stringify(st.rpc).includes("482913") && !JSON.stringify(st.rpc).includes("203.0.113.7"));
});

test("avvia: l'e-mail va all'indirizzo dell'ANAGRAFICA, anche se il client ne manda un altro", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  const r = await gestisci({...DATI, email: "attaccante@esempio.com", a: "attaccante@esempio.com"}, "1.2.3.4", d);
  await Promise.all(st.dopo);
  assert.equal(r.stato, 200);
  assert.equal(st.email.length, 1);
  assert.equal(st.email[0].a, "giovanni@esempio.it");
  assert.match(st.email[0].testo, /482913/);
  assert.match(st.email[0].testo, /10 minuti/);
});

test("avvia: risposta IDENTICA per tesserato riconosciuto e non (anti-enumerazione)", async () => {
  const si = finte({risposte: avviaRisposta(true)}), no = finte({risposte: avviaRisposta(false)});
  const r1 = await gestisci(DATI, "1.2.3.4", si.d), r2 = await gestisci(DATI, "1.2.3.4", no.d);
  assert.deepEqual(r1, r2);
  assert.deepEqual(r1.corpo, {esito: "ok", richiesta: RICHIESTA, messaggio: MESSAGGIO_AVVIO});
  assert.equal(no.st.email.length, 0);
  // Il log non dice se il numero era di un tesserato
  assert.deepEqual(si.st.log.filter(x => !x.includes("invio")), no.st.log);
});

test("avvia: l'invio parte DOPO la risposta (stessi tempi per tesserati e non)", async () => {
  let sblocca; const lento = new Promise(r => { sblocca = r; });
  const {d, st} = finte({risposte: avviaRisposta(true)});
  d.inviaEmail = async m => { st.email.push(m); await lento; };
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.equal(r.stato, 200, "risposta senza aspettare l'invio");
  assert.equal(st.dopo.length, 1);
  sblocca(); await Promise.all(st.dopo);
});

test("avvia: in modalità di prova si scrive SOLO agli indirizzi consentiti", async () => {
  const fuori = finte({risposte: avviaRisposta(true, "socio@esempio.it"), consentite: ["mia.email@esempio.it"]});
  const r = await gestisci(DATI, "1.2.3.4", fuori.d);
  assert.equal(fuori.st.email.length, 0);
  assert.equal(r.stato, 200);
  assert.ok(fuori.st.log.some(x => x.includes("invio_non_consentito")));
  const dentro = finte({risposte: avviaRisposta(true, "Mia.Email@esempio.it"), consentite: ["mia.email@esempio.it"]});
  await gestisci(DATI, "1.2.3.4", dentro.d); await Promise.all(dentro.st.dopo);
  assert.equal(dentro.st.email.length, 1);
});

test("avvia: troppe richieste → 429 uguale per tutti, nessun invio", async () => {
  const {d, st} = finte({risposte: {registrazione_avvia: [{richiesta: null, esito: "troppe_richieste", invia: false}]}});
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 429, corpo: {esito: "troppe_richieste"}});
  assert.equal(st.email.length, 0);
});

test("avvia: dati mancanti o troppo lunghi → 400 senza toccare il database", async () => {
  for (const c of [{...DATI, nome: ""}, {...DATI, cognome: undefined}, {...DATI, telefono: "12"}, {...DATI, nome: "x".repeat(81)}, {...DATI, telefono: 3334444444}]) {
    const {d, st} = finte();
    assert.equal((await gestisci(c, "1.2.3.4", d)).stato, 400);
    assert.equal(st.rpc.length, 0);
  }
});

test("avvia: invio fallito → registrato senza dettagli personali", async () => {
  const {d, st} = finte({risposte: avviaRisposta(true)});
  d.inviaEmail = async () => { throw new Error("SMTP 535 autenticazione rifiutata"); };
  await gestisci(DATI, "1.2.3.4", d); await Promise.all(st.dopo);
  assert.ok(st.log.some(x => x.includes("invio_fallito")));
  assert.equal(segreti(st, "482913", "giovanni@esempio.it", "3334444444", "333 444 4444", "1.2.3.4"), null);
});

// ---------- verifica ----------
const verifica = r => ({registrazione_verifica: [r]});
test("verifica: codice giusto → gettone; al database arriva solo l'HMAC del codice", async () => {
  const {d, st} = finte({risposte: verifica({esito: "ok", token: GETTONE, tentativi_rimasti: 4})});
  const r = await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "482913"}, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 200, corpo: {esito: "ok", gettone: GETTONE}});
  assert.equal(st.rpc[0].a.p_otp_hash, hmac("otp:482913"));
  assert.equal(segreti(st, "482913", GETTONE), null);
});
test("verifica: errato, scaduto, bloccato, riutilizzato → esiti distinti senza gettone", async () => {
  const casi = [
    [{esito: "errato", tentativi_rimasti: 3}, 400, {esito: "errato", tentativi_rimasti: 3}],
    [{esito: "scaduto"}, 410, {esito: "scaduto"}],
    [{esito: "bloccato"}, 429, {esito: "bloccato"}],
    [{esito: "non_valido"}, 400, {esito: "non_valido"}]];
  for (const [db, stato, corpo] of casi) {
    const {d} = finte({risposte: verifica(db)});
    assert.deepEqual(await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "000000"}, "1.2.3.4", d), {stato, corpo});
  }
});
test("verifica: codice non di 6 cifre o richiesta non valida → 400 senza consumare tentativi", async () => {
  for (const c of [{codice: "12345"}, {codice: "1234567"}, {codice: "abcdef"}, {codice: 482913}, {richiesta: "x' or 1=1 --"}]) {
    const {d, st} = finte();
    assert.equal((await gestisci({azione: "verifica", richiesta: RICHIESTA, codice: "482913", ...c}, "1.2.3.4", d)).stato, 400);
    assert.equal(st.rpc.length, 0);
  }
});

// ---------- completa ----------
const gettoneOk = (extra = {}) => ({registrazione_gettone: [{esito: "ok", telefono: "3334444444", nome: "Bianchi Giovanni", account_in_attesa: null, ...extra}]});
const COMPLETA = {azione: "completa", richiesta: RICHIESTA, gettone: GETTONE, pin: "135790"};
test("completa: crea l'account con l'indirizzo calcolato dal telefono del DATABASE e la prova OTP in app_metadata", async () => {
  const {d, st} = finte({risposte: gettoneOk()});
  const r = await gestisci({...COMPLETA, telefono: "3330000000", email: "x@y.it"}, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 200, corpo: {esito: "ok"}});
  assert.equal(st.creati.length, 1);
  const u = st.creati[0];
  assert.equal(u.email, "3334444444@soci.ausergratteri.app");
  assert.equal(u.password, "135790");
  assert.deepEqual(u.app_metadata, {registrazione: RICHIESTA, registrazione_token: sha(GETTONE)});
  assert.ok(!JSON.stringify(u.app_metadata).includes(GETTONE), "il gettone non finisce nei metadati");
  assert.equal(segreti(st, "135790", GETTONE, "3334444444"), null);
});
test("completa: PIN non valido → 400 senza toccare database o account", async () => {
  for (const pin of ["12345", "1234567890123", "abcdef", "", 135790]) {
    const {d, st} = finte({risposte: gettoneOk()});
    assert.deepEqual(await gestisci({...COMPLETA, pin}, "1.2.3.4", d), {stato: 400, corpo: {esito: "pin_non_valido"}});
    assert.equal(st.rpc.length + st.creati.length, 0);
  }
});
test("completa: gettone non valido, scaduto o già usato → nessun account", async () => {
  const {d, st} = finte({risposte: {registrazione_gettone: [{esito: "non_valido"}]}});
  assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 400, corpo: {esito: "non_valido"}});
  assert.equal(st.creati.length, 0);
});
test("completa: numero già registrato come socio → 409, nessun account né cambio PIN", async () => {
  const {d, st} = finte({risposte: {registrazione_gettone: [{esito: "gia_registrato"}]}});
  assert.equal((await gestisci(COMPLETA, "1.2.3.4", d)).stato, 409);
  assert.equal(st.creati.length + st.pin.length, 0);
});
test("completa: doppione (account già creato nel frattempo) → 409 non completabile", async () => {
  const {d} = finte({risposte: gettoneOk(), creaErrore: "email_exists"});
  assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 409, corpo: {esito: "non_completabile"}});
});
test("completa: account 'in attesa' con lo stesso numero → prima il nuovo PIN, poi la promozione", async () => {
  const ATTESA = "77777777-2222-4333-8444-555555555555";
  const {d, st} = finte({risposte: {...gettoneOk({account_in_attesa: ATTESA}), registrazione_riprendi: [{registrazione_riprendi: "ok"}]}});
  assert.deepEqual(await gestisci(COMPLETA, "1.2.3.4", d), {stato: 200, corpo: {esito: "ok"}});
  assert.deepEqual(st.ordine, ["rpc:registrazione_gettone", "pin", "rpc:registrazione_riprendi"]);
  assert.deepEqual(st.pin, [{id: ATTESA, pin: "135790"}]);
  assert.equal(st.creati.length, 0);
});
test("completa: se il PIN dell'account in attesa non cambia, NON si promuove", async () => {
  const ATTESA = "77777777-2222-4333-8444-555555555555";
  const {d, st} = finte({risposte: gettoneOk({account_in_attesa: ATTESA}), pinErrore: "errore"});
  assert.equal((await gestisci(COMPLETA, "1.2.3.4", d)).stato, 500);
  assert.ok(!st.ordine.includes("rpc:registrazione_riprendi"));
});

// ---------- manuale ----------
const MANUALE = {azione: "manuale", nome: "Anna", cognome: "Verdi", telefono: "+39 333 555 0470", pin: "246802"};
test("manuale: account senza app_metadata (resta in attesa), risposta uguale anche se il numero esiste già", async () => {
  const ok = finte({risposte: {registrazione_manuale_consentita: [{x: "ok"}]}});
  const esiste = finte({risposte: {registrazione_manuale_consentita: [{x: "ok"}]}, creaErrore: "email_exists"});
  const r1 = await gestisci(MANUALE, "1.2.3.4", ok.d), r2 = await gestisci(MANUALE, "1.2.3.4", esiste.d);
  assert.deepEqual(r1, r2);
  assert.deepEqual(r1.corpo, {esito: "ricevuta", messaggio: MESSAGGIO_MANUALE});
  assert.equal(ok.st.creati[0].email, "3335550470@soci.ausergratteri.app");
  assert.equal(ok.st.creati[0].app_metadata, undefined, "nessuna prova OTP: il database lo crea in attesa");
  assert.equal(segreti(ok.st, "246802", "3335550470"), null);
});
test("manuale: troppe richieste → 429; PIN non valido → 400", async () => {
  const {d} = finte({risposte: {registrazione_manuale_consentita: [{x: "troppe_richieste"}]}});
  assert.equal((await gestisci(MANUALE, "1.2.3.4", d)).stato, 429);
  const p = finte();
  assert.equal((await gestisci({...MANUALE, pin: "123"}, "1.2.3.4", p.d)).stato, 400);
  assert.equal(p.st.rpc.length, 0);
});

// ---------- generale ----------
test("azione sconosciuta o corpo non valido → 400", async () => {
  for (const c of [null, "testo", 5, {}, {azione: "elimina"}, {azione: "__proto__"}]) {
    const {d} = finte();
    assert.equal((await gestisci(c, "1.2.3.4", d)).stato, 400);
  }
});
test("errore del database → 500 generico, senza dettagli nella risposta", async () => {
  const {d, st} = finte({risposte: {registrazione_avvia: () => { throw new Error("rpc registrazione_avvia: 42501"); }}});
  const r = await gestisci(DATI, "1.2.3.4", d);
  assert.deepEqual(r, {stato: 500, corpo: {esito: "errore"}});
  assert.ok(st.log.some(x => x.includes("42501")));
});
test("codice OTP: sempre 6 cifre, senza distorsioni dai valori alti", () => {
  const visti = new Set();
  for (let i = 0; i < 2000; i++) { const c = codiceDaByte(() => crypto.randomBytes(4).readUInt32BE()); assert.match(c, /^\d{6}$/); visti.add(c); }
  assert.ok(visti.size > 1990, "codici quasi tutti diversi");
  const seq = [4294967295, 4294000000, 7]; let i = 0;
  assert.equal(codiceDaByte(() => seq[i++]), "000007", "i valori oltre il limite vengono scartati");
});
test("messaggio e-mail: nome dell'anagrafica senza HTML, codice e scadenza presenti", () => {
  const m = messaggioEmail("<script>x</script>Rossi", "123456");
  assert.ok(!m.html.includes("<script>"));
  assert.match(m.testo, /123456/); assert.match(m.html, /123456/); assert.match(m.testo, /10 minuti/);
});

// ---------- IP del client ----------
const intest = o => n => o[n] ?? null;
test("IP: si preferisce l'intestazione impostata dal proxy (cf-connecting-ip) a x-forwarded-for", () => {
  assert.deepEqual(ipDaIntestazioni(intest({"cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "1.1.1.1, 203.0.113.9"})), {ip: "203.0.113.9", fonte: "cf-connecting-ip"});
  assert.deepEqual(ipDaIntestazioni(intest({"x-real-ip": "198.51.100.4", "x-forwarded-for": "1.1.1.1"})), {ip: "198.51.100.4", fonte: "x-real-ip"});
  assert.deepEqual(ipDaIntestazioni(intest({"x-forwarded-for": "2001:db8::1, 10.0.0.1"})), {ip: "2001:db8::1", fonte: "x-forwarded-for"});
});
test("IP: valori non validi o iniettati non vengono usati", () => {
  assert.deepEqual(ipDaIntestazioni(intest({"cf-connecting-ip": "1.2.3.4'; drop table x;--", "x-forwarded-for": "<script>"})), {ip: "sconosciuto", fonte: "nessuna"});
  assert.deepEqual(ipDaIntestazioni(intest({})), {ip: "sconosciuto", fonte: "nessuna"});
  assert.equal(ipDaIntestazioni(intest({"x-real-ip": "x".repeat(100)})).fonte, "nessuna");
});
test("IP falsificato a ogni richiesta: il limite per numero resta (deciso dal database, non dall'IP)", async () => {
  // Il database conta per numero di telefono: qui la seconda richiesta, con un IP diverso, è comunque respinta
  let n = 0;
  const {d} = finte({risposte: {registrazione_avvia: () => [n++ === 0 ? {richiesta: RICHIESTA, esito: "ok", invia: false} : {richiesta: null, esito: "troppe_richieste", invia: false}]}});
  assert.equal((await gestisci(DATI, "1.1.1.1", d)).stato, 200);
  assert.equal((await gestisci(DATI, "9.9.9.9", d)).stato, 429);
});
